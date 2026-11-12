# V2 calibration review — preserve the gate, no automatic retune

V2 improved confirmation from 25% to 62.5%, but needs at least 6/8 (75%).
It allowed 5/8, with 0 unsafe allows. This is a usefulness/false-refusal problem,
not an API connection failure. The strict thresholds are 0.95 support / 0.10 conflict.

| Refused answerable fixture | Support | Conflict | Why refused |
| --- | --- | --- | --- |
| VI Xenon repair: final 700 thousand, customer supplied brakes | 0.87 | 0.11 | support too low and conflict too high |
| VI Ceres garden meeting: east yard, Saturday 08:00, west yard under repair | 0.94 | 0.07 | support below 0.95 |
| EN Rowan reading circle: room South, Saturday 16:00, North under repair | 0.90 | 0.06 | support below 0.95 |

These fixture labels are author-claimed, not independent human-reviewed truth.
The model struggles most with explicitly resolved updates and multiple requested
facts. Scope/retrieval cannot explain these results: JEV received the entire
frozen fixture evidence directly.

Do not lower thresholds based on these confirmation results. That would tune
on the test set and discard the promised held-out gate. Do not send these
requests to DeepSeek merely because a human can see the answer.

Next decision: review these three gold cases and the false-refusal trade-off
before another calibration experiment. Keep the existing 75% / zero-unsafe gate
until explicitly revised. No third provider loop is running. Remaining16calls
cannot support another32+32 calibration; any extension needs a concrete new plan.
