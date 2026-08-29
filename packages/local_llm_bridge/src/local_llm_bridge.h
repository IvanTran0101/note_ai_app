/*
 * C ABI facade for the local_llm_bridge package.
 *
 * This header is the only stable interface between Dart and native code.
 * Dart must never see C++ classes, llama.cpp types, or native object layout.
 * All buffers crossing the ABI are caller-owned. Runtime handles are opaque
 * pointers owned by the facade and must be released with runtime_free().
 */
#ifndef LOCAL_LLM_BRIDGE_H
#define LOCAL_LLM_BRIDGE_H

#include <stdint.h>

#if defined(_WIN32)
#define LOCAL_LLM_BRIDGE_EXPORT __declspec(dllexport)
#else
#define LOCAL_LLM_BRIDGE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Writes the native bridge version into a caller-owned buffer. */
LOCAL_LLM_BRIDGE_EXPORT int32_t local_llm_bridge_smoke_version(
    char* buffer, int32_t capacity);

/* Echoes a single integer across the ABI boundary. */
LOCAL_LLM_BRIDGE_EXPORT int32_t local_llm_bridge_smoke_echo(int32_t value);

typedef void* local_llm_bridge_runtime_handle;

enum local_llm_bridge_status {
  LOCAL_LLM_BRIDGE_STATUS_OK = 0,
  LOCAL_LLM_BRIDGE_STATUS_INVALID_ARGUMENT = 1,
  LOCAL_LLM_BRIDGE_STATUS_MODEL_LOAD_FAILED = 2,
  LOCAL_LLM_BRIDGE_STATUS_CONTEXT_CREATE_FAILED = 3,
  LOCAL_LLM_BRIDGE_STATUS_TOKENIZE_FAILED = 4,
  LOCAL_LLM_BRIDGE_STATUS_DECODE_FAILED = 5,
  LOCAL_LLM_BRIDGE_STATUS_OUTPUT_TOO_SMALL = 6,
  LOCAL_LLM_BRIDGE_STATUS_GENERATION_FAILED = 7,
};

/*
 * Loads a GGUF model and creates one CPU inference context.
 *
 * `context_size` and `threads` use low-tier defaults when zero. The returned
 * handle is owned by the caller and must be released with runtime_free().
 * `status` is required and receives a local_llm_bridge_status value. On
 * failure, NULL is returned and the optional error buffer is populated.
 */
LOCAL_LLM_BRIDGE_EXPORT local_llm_bridge_runtime_handle
local_llm_bridge_runtime_create(const char* model_path,
                                int32_t context_size,
                                int32_t threads,
                                int32_t* status,
                                char* error_buffer,
                                int32_t error_capacity);

/* Releases a handle returned by runtime_create(). NULL is accepted. */
LOCAL_LLM_BRIDGE_EXPORT void local_llm_bridge_runtime_free(
    local_llm_bridge_runtime_handle runtime);

/*
 * Runs one independent, greedy generation request.
 *
 * `prompt` is a complete prompt. Model-specific chat formatting is owned by a
 * higher application layer in a later slice.
 * The context memory is cleared at the start of every request. On success,
 * `*output_length` is the UTF-8 byte count excluding the NUL terminator.
 * `output_capacity` includes room for that terminator. If the buffer is too
 * small, the function returns OUTPUT_TOO_SMALL and writes the required byte
 * count to `*output_length`; the caller may retry the request.
 *
 * The output and error buffers remain caller-owned. The handle is not safe to
 * free while a request is running, but repeated requests are serialized by
 * the facade.
 */
LOCAL_LLM_BRIDGE_EXPORT int32_t local_llm_bridge_runtime_generate(
    local_llm_bridge_runtime_handle runtime,
    const char* prompt,
    int32_t max_tokens,
    char* output_buffer,
    int32_t output_capacity,
    int32_t* output_length,
    char* error_buffer,
    int32_t error_capacity);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // LOCAL_LLM_BRIDGE_H
