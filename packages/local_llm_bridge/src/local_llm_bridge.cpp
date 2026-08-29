#include "local_llm_bridge.h"

#include "llama.h"

#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* kSmokeVersion = "local_llm_bridge 0.0.1-smoke (C ABI)";
constexpr int32_t kDefaultContextSize = 2048;
constexpr int32_t kDefaultThreads = 4;
constexpr int32_t kMaxContextSize = 4096;
constexpr int32_t kMaxGenerationTokens = 512;
constexpr uint32_t kMaxBatchSize = 512;

std::once_flag g_backend_init;

struct Runtime {
  llama_model* model = nullptr;
  llama_context* context = nullptr;
  int32_t context_size = 0;
  std::mutex request_mutex;

  ~Runtime() {
    if (context != nullptr) {
      llama_free(context);
    }
    if (model != nullptr) {
      llama_model_free(model);
    }
  }
};

struct SamplerDeleter {
  void operator()(llama_sampler* sampler) const {
    if (sampler != nullptr) {
      llama_sampler_free(sampler);
    }
  }
};

using SamplerPtr = std::unique_ptr<llama_sampler, SamplerDeleter>;

struct ModelDeleter {
  void operator()(llama_model* model) const {
    if (model != nullptr) {
      llama_model_free(model);
    }
  }
};

struct ContextDeleter {
  void operator()(llama_context* context) const {
    if (context != nullptr) {
      llama_free(context);
    }
  }
};

void clear_error(char* buffer, int32_t capacity) {
  if (buffer != nullptr && capacity > 0) {
    buffer[0] = '\0';
  }
}

void set_error(char* buffer, int32_t capacity, const char* format, ...) {
  if (buffer == nullptr || capacity <= 0) {
    return;
  }

  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, static_cast<size_t>(capacity), format, args);
  va_end(args);
  buffer[capacity - 1] = '\0';
}

int32_t default_thread_count() {
  const unsigned hardware_threads = std::thread::hardware_concurrency();
  if (hardware_threads == 0) {
    return 2;
  }
  return static_cast<int32_t>(std::min<unsigned>(hardware_threads,
                                                  kDefaultThreads));
}

void initialize_backend() {
  std::call_once(g_backend_init, []() { llama_backend_init(); });
}

int32_t token_count_for_prompt(const llama_vocab* vocab,
                               const char* prompt,
                               char* error_buffer,
                               int32_t error_capacity) {
  const size_t prompt_length = std::strlen(prompt);
  if (prompt_length > static_cast<size_t>(std::numeric_limits<int32_t>::max())) {
    set_error(error_buffer, error_capacity, "prompt is too large");
    return -1;
  }

  const int32_t token_count = llama_tokenize(
      vocab, prompt, static_cast<int32_t>(prompt_length), nullptr, 0, true,
      true);
  if (token_count == std::numeric_limits<int32_t>::min()) {
    set_error(error_buffer, error_capacity, "prompt token count overflowed");
    return -1;
  }

  if (token_count < 0) {
    return -token_count;
  }

  return token_count;
}

bool append_token_piece(const llama_vocab* vocab,
                        llama_token token,
                        std::string* output,
                        char* error_buffer,
                        int32_t error_capacity) {
  std::vector<char> piece(256);
  int32_t piece_length = llama_token_to_piece(
      vocab, token, piece.data(), static_cast<int32_t>(piece.size()), 0, true);
  if (piece_length == std::numeric_limits<int32_t>::min()) {
    set_error(error_buffer, error_capacity, "token piece length overflowed");
    return false;
  }

  if (piece_length < 0) {
    const int32_t required = -piece_length;
    if (required <= 0) {
      set_error(error_buffer, error_capacity, "invalid token piece length");
      return false;
    }
    piece.resize(static_cast<size_t>(required));
    piece_length = llama_token_to_piece(vocab, token, piece.data(), required,
                                        0, true);
  }

  if (piece_length < 0) {
    set_error(error_buffer, error_capacity,
              "failed to convert sampled token to UTF-8");
    return false;
  }

  output->append(piece.data(), static_cast<size_t>(piece_length));
  return true;
}

/*
 * Formats a system/user turn with the model's chat template and appends the
 * assistant turn start. On success returns OK and fills `formatted`; the
 * caller must hold the request mutex.
 */
int32_t format_chat_prompt(const llama_model* model,
                           const char* system_prompt,
                           const char* user_prompt,
                           std::string* formatted,
                           char* error_buffer,
                           int32_t error_capacity) {
  const char* chat_template = llama_model_chat_template(model, nullptr);
  if (chat_template == nullptr) {
    set_error(error_buffer, error_capacity,
              "model has no chat template; chat generation is unavailable");
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_MISSING;
  }

  const llama_chat_message messages[] = {
      {"system", system_prompt},
      {"user", user_prompt},
  };
  constexpr size_t kMessageCount = 2;

  const int32_t required = llama_chat_apply_template(
      chat_template, messages, kMessageCount, /*add_ass=*/true, nullptr, 0);
  if (required < 0) {
    set_error(error_buffer, error_capacity,
              "llama.cpp does not support the model chat template");
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED;
  }
  if (required == std::numeric_limits<int32_t>::max()) {
    set_error(error_buffer, error_capacity,
              "formatted chat prompt is too large");
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED;
  }

  std::vector<char> buffer(static_cast<size_t>(required) + 1);
  const int32_t written = llama_chat_apply_template(
      chat_template, messages, kMessageCount, /*add_ass=*/true, buffer.data(),
      static_cast<int32_t>(buffer.size()));
  if (written < 0 || written > required) {
    set_error(error_buffer, error_capacity,
              "llama.cpp failed to render the model chat template");
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED;
  }

  formatted->assign(buffer.data(), static_cast<size_t>(written));
  return LOCAL_LLM_BRIDGE_STATUS_OK;
}

/*
 * Runs one greedy generation for a complete prompt. Output/error semantics
 * match the public ABI. The caller must hold runtime->request_mutex and have
 * validated the runtime, max_tokens, and output_length arguments.
 */
int32_t run_generation(Runtime* runtime,
                       const char* prompt,
                       int32_t max_tokens,
                       char* output_buffer,
                       int32_t output_capacity,
                       int32_t* output_length,
                       char* error_buffer,
                       int32_t error_capacity) {
  try {
    llama_memory_clear(llama_get_memory(runtime->context), true);

    const llama_vocab* vocab = llama_model_get_vocab(runtime->model);
    const int32_t prompt_token_count =
        token_count_for_prompt(vocab, prompt, error_buffer, error_capacity);
    if (prompt_token_count <= 0) {
      if (prompt_token_count == 0) {
        set_error(error_buffer, error_capacity,
                  "prompt produced no tokens");
      }
      return LOCAL_LLM_BRIDGE_STATUS_TOKENIZE_FAILED;
    }

    std::vector<llama_token> prompt_tokens(
        static_cast<size_t>(prompt_token_count));
    const size_t prompt_length = std::strlen(prompt);
    const int32_t tokenized = llama_tokenize(
        vocab, prompt, static_cast<int32_t>(prompt_length),
        prompt_tokens.data(), prompt_token_count, true, true);
    if (tokenized < 0 || tokenized != prompt_token_count) {
      set_error(error_buffer, error_capacity,
                "llama.cpp failed to tokenize the prompt");
      return LOCAL_LLM_BRIDGE_STATUS_TOKENIZE_FAILED;
    }

    const int64_t required_context =
        static_cast<int64_t>(prompt_token_count) + max_tokens;
    if (required_context > runtime->context_size) {
      set_error(error_buffer, error_capacity,
                "prompt plus max_tokens exceeds context size");
      return LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
    }

    SamplerPtr sampler(llama_sampler_chain_init(
        llama_sampler_chain_default_params()));
    if (!sampler) {
      set_error(error_buffer, error_capacity,
                "llama.cpp could not create the sampler");
      return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
    }
    llama_sampler* greedy_sampler = llama_sampler_init_greedy();
    if (greedy_sampler == nullptr) {
      set_error(error_buffer, error_capacity,
                "llama.cpp could not create the greedy sampler");
      return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
    }
    llama_sampler_chain_add(sampler.get(), greedy_sampler);

    llama_batch batch = llama_batch_get_one(
        prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));
    if (llama_model_has_encoder(runtime->model)) {
      if (llama_encode(runtime->context, batch) != 0) {
        set_error(error_buffer, error_capacity,
                  "llama.cpp failed to encode the prompt");
        return LOCAL_LLM_BRIDGE_STATUS_DECODE_FAILED;
      }

      llama_token decoder_start =
          llama_model_decoder_start_token(runtime->model);
      if (decoder_start == LLAMA_TOKEN_NULL) {
        decoder_start = llama_vocab_bos(vocab);
      }
      batch = llama_batch_get_one(&decoder_start, 1);
      if (llama_decode(runtime->context, batch) != 0) {
        set_error(error_buffer, error_capacity,
                  "llama.cpp failed to decode the decoder start token");
        return LOCAL_LLM_BRIDGE_STATUS_DECODE_FAILED;
      }
    } else if (llama_decode(runtime->context, batch) != 0) {
      set_error(error_buffer, error_capacity,
                "llama.cpp failed to decode the prompt");
      return LOCAL_LLM_BRIDGE_STATUS_DECODE_FAILED;
    }

    std::string generated;
    generated.reserve(static_cast<size_t>(max_tokens) * 4);
    for (int32_t generated_tokens = 0; generated_tokens < max_tokens;
         ++generated_tokens) {
      llama_token next_token =
          llama_sampler_sample(sampler.get(), runtime->context, -1);
      if (next_token == LLAMA_TOKEN_NULL) {
        set_error(error_buffer, error_capacity,
                  "llama.cpp sampler returned no token");
        return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
      }
      if (llama_vocab_is_eog(vocab, next_token)) {
        break;
      }
      if (!append_token_piece(vocab, next_token, &generated, error_buffer,
                              error_capacity)) {
        return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
      }

      if (generated_tokens + 1 < max_tokens &&
          llama_decode(runtime->context,
                        llama_batch_get_one(&next_token, 1)) != 0) {
        set_error(error_buffer, error_capacity,
                  "llama.cpp failed to decode a generated token");
        return LOCAL_LLM_BRIDGE_STATUS_DECODE_FAILED;
      }
    }

    if (generated.size() >
        static_cast<size_t>(std::numeric_limits<int32_t>::max())) {
      set_error(error_buffer, error_capacity, "generated output is too large");
      return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
    }

    const int32_t generated_length = static_cast<int32_t>(generated.size());
    *output_length = generated_length;
    if (output_buffer == nullptr || output_capacity <= generated_length) {
      set_error(error_buffer, error_capacity,
                "output buffer too small; need %d bytes plus NUL",
                generated_length);
      return LOCAL_LLM_BRIDGE_STATUS_OUTPUT_TOO_SMALL;
    }

    std::memcpy(output_buffer, generated.data(), generated.size());
    output_buffer[generated_length] = '\0';
    return LOCAL_LLM_BRIDGE_STATUS_OK;
  } catch (const std::exception& exception) {
    set_error(error_buffer, error_capacity, "generation failed: %s",
              exception.what());
    return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
  } catch (...) {
    set_error(error_buffer, error_capacity, "generation failed");
    return LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED;
  }
}

}  // namespace

int32_t local_llm_bridge_smoke_version(char* buffer, int32_t capacity) {
  const size_t required = std::strlen(kSmokeVersion) + 1;
  if (buffer == nullptr || capacity < static_cast<int32_t>(required)) {
    return static_cast<int32_t>(required);
  }
  std::memcpy(buffer, kSmokeVersion, required);
  return static_cast<int32_t>(required - 1);
}

int32_t local_llm_bridge_smoke_echo(int32_t value) { return value; }

local_llm_bridge_runtime_handle local_llm_bridge_runtime_create(
    const char* model_path,
    int32_t context_size,
    int32_t threads,
    int32_t* status,
    char* error_buffer,
    int32_t error_capacity) {
  clear_error(error_buffer, error_capacity);

  if (status == nullptr) {
    set_error(error_buffer, error_capacity, "status output is required");
    return nullptr;
  }
  *status = LOCAL_LLM_BRIDGE_STATUS_OK;

  if (model_path == nullptr || model_path[0] == '\0') {
    *status = LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
    set_error(error_buffer, error_capacity, "model path must not be empty");
    return nullptr;
  }
  if (context_size < 0 || threads < 0) {
    *status = LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
    set_error(error_buffer, error_capacity,
              "context size and threads must not be negative");
    return nullptr;
  }

  const int32_t resolved_context_size =
      context_size == 0 ? kDefaultContextSize : context_size;
  const int32_t resolved_threads =
      threads == 0 ? default_thread_count() : threads;
  if (resolved_context_size < 2 || resolved_context_size > kMaxContextSize ||
      resolved_threads < 1) {
    *status = LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
    set_error(error_buffer, error_capacity,
              "context size must be between 2 and %d; threads must be at least 1",
              kMaxContextSize);
    return nullptr;
  }

  try {
    initialize_backend();

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;

    ModelDeleter model_deleter;
    std::unique_ptr<llama_model, ModelDeleter> model(
        llama_model_load_from_file(model_path, model_params), model_deleter);
    if (!model) {
      *status = LOCAL_LLM_BRIDGE_STATUS_MODEL_LOAD_FAILED;
      set_error(error_buffer, error_capacity,
                "llama.cpp could not load the GGUF model");
      return nullptr;
    }

    const int32_t trained_context = llama_model_n_ctx_train(model.get());
    if (trained_context > 0 && resolved_context_size > trained_context) {
      *status = LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
      set_error(error_buffer, error_capacity,
                "context size exceeds model training context");
      return nullptr;
    }

    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(resolved_context_size);
    context_params.n_batch = static_cast<uint32_t>(resolved_context_size);
    context_params.n_ubatch =
        std::min<uint32_t>(static_cast<uint32_t>(resolved_context_size),
                           kMaxBatchSize);
    context_params.n_seq_max = 1;
    context_params.n_threads = resolved_threads;
    context_params.n_threads_batch = resolved_threads;
    context_params.no_perf = true;

    ContextDeleter context_deleter;
    std::unique_ptr<llama_context, ContextDeleter> context(
        llama_init_from_model(model.get(), context_params), context_deleter);
    if (!context) {
      *status = LOCAL_LLM_BRIDGE_STATUS_CONTEXT_CREATE_FAILED;
      set_error(error_buffer, error_capacity,
                "llama.cpp could not create the inference context");
      return nullptr;
    }

    auto runtime = std::make_unique<Runtime>();
    runtime->model = model.release();
    runtime->context = context.release();
    runtime->context_size = static_cast<int32_t>(llama_n_ctx(runtime->context));
    return runtime.release();
  } catch (const std::exception& exception) {
    *status = LOCAL_LLM_BRIDGE_STATUS_MODEL_LOAD_FAILED;
    set_error(error_buffer, error_capacity, "runtime creation failed: %s",
              exception.what());
    return nullptr;
  } catch (...) {
    *status = LOCAL_LLM_BRIDGE_STATUS_MODEL_LOAD_FAILED;
    set_error(error_buffer, error_capacity, "runtime creation failed");
    return nullptr;
  }
}

void local_llm_bridge_runtime_free(local_llm_bridge_runtime_handle handle) {
  delete static_cast<Runtime*>(handle);
}

int32_t local_llm_bridge_runtime_generate(
    local_llm_bridge_runtime_handle handle,
    const char* prompt,
    int32_t max_tokens,
    char* output_buffer,
    int32_t output_capacity,
    int32_t* output_length,
    char* error_buffer,
    int32_t error_capacity) {
  clear_error(error_buffer, error_capacity);
  if (output_length != nullptr) {
    *output_length = 0;
  }

  auto* runtime = static_cast<Runtime*>(handle);
  if (runtime == nullptr || runtime->model == nullptr ||
      runtime->context == nullptr || prompt == nullptr ||
      output_length == nullptr) {
    set_error(error_buffer, error_capacity,
              "runtime, prompt, and output length are required");
    return LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
  }
  if (max_tokens < 1 || max_tokens > kMaxGenerationTokens ||
      max_tokens >= runtime->context_size) {
    set_error(error_buffer, error_capacity,
              "max_tokens must be between 1 and %d and fit the context",
              kMaxGenerationTokens);
    return LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
  }

  std::lock_guard<std::mutex> request_lock(runtime->request_mutex);
  return run_generation(runtime, prompt, max_tokens, output_buffer,
                        output_capacity, output_length, error_buffer,
                        error_capacity);
}

int32_t local_llm_bridge_runtime_generate_chat(
    local_llm_bridge_runtime_handle handle,
    const char* system_prompt,
    const char* user_prompt,
    int32_t max_tokens,
    char* output_buffer,
    int32_t output_capacity,
    int32_t* output_length,
    char* error_buffer,
    int32_t error_capacity) {
  clear_error(error_buffer, error_capacity);
  if (output_length != nullptr) {
    *output_length = 0;
  }

  auto* runtime = static_cast<Runtime*>(handle);
  if (runtime == nullptr || runtime->model == nullptr ||
      runtime->context == nullptr || system_prompt == nullptr ||
      user_prompt == nullptr || output_length == nullptr) {
    set_error(error_buffer, error_capacity,
              "runtime, prompts, and output length are required");
    return LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
  }
  if (max_tokens < 1 || max_tokens > kMaxGenerationTokens ||
      max_tokens >= runtime->context_size) {
    set_error(error_buffer, error_capacity,
              "max_tokens must be between 1 and %d and fit the context",
              kMaxGenerationTokens);
    return LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT;
  }

  std::lock_guard<std::mutex> request_lock(runtime->request_mutex);

  std::string formatted_prompt;
  int32_t format_status;
  try {
    format_status = format_chat_prompt(runtime->model, system_prompt,
                                       user_prompt, &formatted_prompt,
                                       error_buffer, error_capacity);
  } catch (const std::exception& exception) {
    set_error(error_buffer, error_capacity, "chat template formatting failed: %s",
              exception.what());
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED;
  } catch (...) {
    set_error(error_buffer, error_capacity, "chat template formatting failed");
    return LOCAL_LLM_BRIDGE_STATUS_CHAT_TEMPLATE_FAILED;
  }
  if (format_status != LOCAL_LLM_BRIDGE_STATUS_OK) {
    return format_status;
  }

  return run_generation(runtime, formatted_prompt.c_str(), max_tokens,
                        output_buffer, output_capacity, output_length,
                        error_buffer, error_capacity);
}
