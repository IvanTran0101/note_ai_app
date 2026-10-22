# Generic low-end Android test pack

Start with [the ver2 handoff](../../LOW_END_ANDROID_VER2.md).

The corpus, checklist, and CSV templates are preserved from the supplied
teammate test pack. The checklist describes the original `a874e517` baseline,
whose RAM gates were unset. The ver2 production catalog now applies the
user-requested 2 GiB Gemma 3 / 6 GiB Gemma 4 RAM policy. Record the actual
ver2 commit in new result rows and distinguish it from baseline observations.

Copy the three `.template.csv` files into a separate results directory before
collecting data. All device runs and quality results are pending in these
templates. Do not overwrite them with fabricated or expected observations.

Corpus identity: `generic_roles_v2`.
SHA-256: `f97d2009224c81f9213d15e6a1b0b411a37849df6082be3c27d7ed03545605eb`.

Store actual raw input/output, timings, failures, screenshots, and memory/frame
evidence by run ID. Keep first download, cold process startup, and warm summaries
separate. Independent human quality reviews and other devices remain pending.
