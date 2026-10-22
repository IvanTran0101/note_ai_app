# NoteFlow results to collect for the midterm report

Please complete the following evidence for the midterm source baseline identified in Appendix A of the report (short commit a874e517, branch note-ai-app). Return the raw files as well as the completed tables. If code changes are necessary, record the new revision and identify which results use it; do not mix revisions without explanation.

The report currently has 22 passing source checks and 84 passing existing tests in a portable fixture. These do not establish a full native application test pass, phone inference, phone performance, or model quality. No phone measurements have been supplied. The Windows full-app native test attempt failed before test execution, and static analysis did not complete. Do not repeat the existing portable checks merely to produce more screenshots.

## 1. Device and model identity — Table 9

For every tested device and configuration, supply:

- Exact phone/computer model and hardware variant, OS version, architecture/ABI, total RAM and available storage before model preparation.
- Flutter/Dart version, target platform, build mode, build identifier and source revision. Use profile mode for frame profiling; distinguish release latency measurements from profile-mode measurements.
- Display refresh rate and the device's power/thermal conditions, such as charging state and whether runs were performed back to back.
- Actual language-model name, artifact filename, source revision, file size and SHA-256 checksum. Record checksum agreement with the expected catalog value.
- Actual native runtime revision, context size, maximum output tokens and resolved native CPU thread count. A configured zero means automatic selection, not zero threads: the runtime caps reported hardware concurrency at four and uses two if that value is unknown. Record whether the resolved count was observed or derived from the source.
- Startup mode: automatic mobile download or an explicitly supplied local model path; authentication mode and whether a session was already established.

Use at least one physical Android or iOS phone for the local-AI evidence. A second phone is useful for resource comparison, but two Android phones are not two operating-system platforms. A second platform demonstration is listed separately below.

Important comparison condition: automatic selection currently prioritizes Gemma 4 when both models are compatible. Do not claim the app automatically chooses the smaller model for low-RAM phones. Testing a manually supplied Gemma 3 model may use a different configuration path: mobile descriptors request 4096 context / 512 output, while the explicit-path defaults are 2048 / 128. Match settings for a controlled model comparison or disclose the difference and avoid attributing every difference to the model alone.

## 2. Native build and application verification

- Complete static analysis and return its entire output and exit status, including any unresolved findings.
- Return a successful native build log and a directly runnable artifact, then demonstrate installation and launch on the target device. A successful dependency resolution or Web build is insufficient for this claim.
- Run the applicable full-project tests with a working native toolchain. Return the complete log, passed/failed/skipped counts and platform. Include the download, integrity, storage, model-manager and worker-lifecycle suites that were not established by the portable fixture.
- Demonstrate at least one request through the installed app to the real native runtime. An opt-in smoke test that skipped, a fake worker response, or a host-only smoke test does not establish phone execution.
- Record setup instructions that another teammate can follow on the demonstrated platform. The pinned checkout already contains lib/amplify_outputs.dart. The recorded isolated local-auth build used an empty replacement scaffold; preserve the original configuration and use configuration matching the intended deployment for Cognito/sync testing.

If a check remains blocked, report it as blocked with the reason and log. Do not convert blocked or skipped checks into passes.

## 3. Model preparation and reuse

Collect screenshots/video plus logs for:

1. First mobile download: model identity, visible progress, completed bytes, checksum verification, committed artifact and successful runtime-ready state. Record download duration and network conditions separately from offline inference timing.
2. Cached restart: restart the process, reuse the valid model without downloading again, verify its integrity and load the native runtime.
3. Repeated requests: reuse the loaded worker; show that each summary request does not reload the model.

The existing device CSV contains verification and loading timing columns; record first-download timing in a separate setup log or add a clearly named column.

## 4. Fresh offline inference — Table 10

Prepare the model and establish any required login session first. Then disable Wi-Fi and mobile data and record a NEW request with a previously recorded input. Keep a video/screenshot of connectivity state, the request and the real returned summary, with a run identifier linking it to logs.

State the offline scope precisely: a prepared model and existing session are allowed preconditions; account registration, initial download and cloud synchronization are not demonstrated as offline. Displaying an old summary is not a new offline inference result.

## 5. Timing, memory and long-note behavior — Table 10

For each model/configuration being compared, collect:

| Missing measurement | Evidence to return |
| --- | --- |
| Cached artifact integrity verification | Duration in ms, timing boundaries and raw log |
| Native runtime loading | Separate duration in ms and success/failure |
| Cold-process request | First request after process restart; state that OS file caches may remain warm |
| Warm short-note summary | At least 10 timed requests for the selected workload, reusing the worker; keep every raw duration and failure |
| Warm long-note summary | At least 10 timed requests for the selected workload; keep input, chunk count, generation-call count and durations |
| Peak process memory | Baseline, loading peak and generation peak; units, tool, process scope and sampling interval |
| Stable reuse | Memory observations across repeated requests and after leaving the screen/restarting the process |

The ten-run minimum is the report's chosen evaluation protocol, not a separately stated teacher rule. More than one cold-process observation is preferable when time permits. Do not pool cold and warm runs or different devices into one unexplained average. Report count, median and spread; retain failed/time-out runs in the record. If reporting p95, name the calculation method because ten observations give a coarse tail estimate.

Stop the summary timer when the service returns the completed result, before the typewriter reveal animation. The current bridge does not expose per-token timing or token counts: leave first-token latency and decode tokens/second unavailable unless you actually add and validate instrumentation. Do not calculate them from assumed token counts.

For a genuine long-note run, retain the full source note, chunk ordering, merge rounds and final output. Confirm that important facts near both the beginning and end survive. The prepared LONG01 fixture exceeds the mobile input estimate. Actual tokenization can still reject a request; keep that failure rather than silently truncating the note. Three worker calls were observed for one short-intermediate-output fixture; do not assume every two-chunk input always takes three calls. Recursive merging has no explicit progress check or round limit. If a test harness imposes a timeout, record its duration and distinguish it from an app-provided timeout or native cancellation.

## 6. UI responsiveness — Table 10

Supply profile-mode frame traces during artifact verification/loading and during real native inference, accompanied by a screen recording of an interaction that the UI permits, such as scrolling or selection. Hashing runs on the caller's isolate, so preparation responsiveness also needs evidence. Record display refresh rate, phase intervals, UI/build and raster durations, and frames exceeding the relevant frame budget. State the tool and calculation used. A worker isolate alone does not establish continued execution while the OS suspends the app.

A moving spinner or typewriter animation alone is insufficient. The app intentionally disables some editing actions while busy; do not claim that every control remains available. The relevant nominal budgets are approximately 16.7 ms at 60 Hz and 8.3 ms at 120 Hz, interpreted with actual frame data.

The assignment asks the team to measure and improve loading/inference experience. Show a measured baseline and a justified improvement if available, retaining the original baseline revision/configuration and the changed one. If no improvement is measured, state that limitation and remove claims of a measured speedup. Isolate usage alone does not establish a before/after improvement.

## 7. Failure, cancellation and recovery evidence — Tables 6 and 10

Record the steps, expected behavior, actual behavior, pass/fail/blocked status, raw log and screenshot/video for each relevant case:

| Case | What must be observed |
| --- | --- |
| Interrupted download / network loss | Clear failure, no false-ready state, staging cleanup, note preserved, successful retry when possible |
| User cancels model preparation | Cancellation feedback and cleanup; a later retry can prepare the model |
| Wrong-size or wrong-checksum artifact | Artifact rejected and no runtime-ready state; invalid cache removal is best-effort and the attempt fails. Record actual cleanup; replacement requires a later attempt |
| Storage write failure / insufficient storage | Clear failure, no partial model accepted, original note preserved; use a controlled test fixture if necessary and label it as such |
| Missing/incompatible model or runtime load failure | Clear loading failure and safe return to the note; retain device evidence for real failures |
| Blank input and empty native output | Validation/error handling without a fabricated summary; distinguish automated boundary evidence from an actual model run |
| Context overflow / too many chunks | Explicit bounded failure and no silent input truncation |
| Navigate away, screen disposal or permitted account switch during work | No crash or result attached to the wrong note/account; if a transition is disabled, record that behavior |
| Edit after generating a summary | Old result is marked stale or otherwise clearly associated with its original content |
| Reopen/retry after failure | Note content remains intact and a valid later request can succeed |

The current native decode has no cooperative abort. Demonstrate preparation cancellation where supported, but do not claim that pressing a control terminates an active native generation. An invalidated UI result or a queued shutdown message is not native cancellation. Controlled automated failures can complement device tests; label their scope rather than presenting them as phone measurements.

## 8. Real model outputs and quality scores — Table 11

Use the included evaluation_corpus.json, version generic_roles_v2, without changing its reference facts after seeing the summaries. It contains 10 fixtures using generic roles: English, Vietnamese, revised deadlines, mixed language, adversarial instructions, dense identifiers, blank input and a long note. Run both catalog models on the same valid notes where the device supports them; document any model that cannot load rather than inventing a result.

For each fixture/model/run, return the exact input and unedited output text, run identifier, model/configuration, status and any failure. Score:

- Mandatory facts retained, with the number of applicable required facts as denominator.
- Unsupported claims, changed names/identifiers/numbers/dates, and omissions.
- English/Vietnamese language compliance, including the mixed-language case.
- Facts retained through long-note chunking and merging.
- Behavior on the quoted adversarial instructions.
- Any truncation, empty output, timeout or load/generation failure.

The blank-input fixture is expected to be rejected before generation; report it as a validation case, not a model-quality success or failure. Keep failed generation rows and state how they affect aggregate scores. Have two teammates independently assess an identified subset and record their disagreements and resolution. At minimum, insert a real short-note and long-note input/output example with device-labelled screenshots into Chapter 6; supply examples for each successfully evaluated model.

## 9. Second supported platform and core note workflow

Demonstrate a second operating-system platform, including installation/launch and create, save, reopen, edit and delete a note. Record the platform, build and actual outcomes. Explain which platform supports local AI and which has an explicit limitation.

The observed Web editor cannot save notes, so it does not yet establish a complete second-platform core workflow. Prefer another supported native platform, or fix and demonstrate Web persistence with its AI limitation stated. Web is not a phone model-download or inference test. An exception to the course's two-platform expectation must be explicitly justified rather than silently assumed.

If the report/demo claims live Cognito authentication or cloud synchronization works, also return authorized-environment evidence for those claims, including failure handling and account separation. Otherwise keep the current source-design description and do not imply a new backend deployment was tested.

## 10. Files to return and report updates

Fill device_runs.csv and quality_results.csv. Add test_results.csv for the checks above; every result needs its evidence-file path. Return raw outputs, timing logs, frame/memory traces, screenshots, the runnable release artifact/build log, completed analyzer/test logs and reproduction instructions. Keep units and device/model labels explicit.

After results exist, add readable charts for the comparisons actually supported by the data: cold/warm latency distributions, verification versus loading cost, memory across phases, frame timings during inference and model-quality comparisons. A table can replace a chart when it communicates the evidence better. Do not draw performance bars from catalog sizes or guessed numbers. The report already includes a catalog-size chart, clearly labelled as metadata.

Replace all TO ADD fields in Chapter 6 Tables 9–11, interpret the findings, update the abstract and conclusion, then refresh the contents and figure/table lists and export the PDF again. A failed model load is a valid result when its conditions and consequences are explained.

The revised report currently has 26 chapter pages, or 30 pages including the abstract, contents and figure/table lists. Replace the insertion guidance with concise results and use appendices for raw traces and extra screenshots so the final report stays within the assignment's 20–35-page range, excluding the cover, references and appendices.

Energy use and accelerator comparisons are optional extensions unless you claim measured benefits. Do not infer energy consumption from a brief battery-percentage change. Quantization-quality claims require a suitable same-model precision baseline; the two different Gemma generations alone do not isolate quantization effects.

Outside testing, the submission still needs the required video, complete source/configuration archive and tested README. Confirm the cover's course number: the team supplied 502071, whereas the assignment identifies 503107.
