# M03 native picker lifecycle correction

Actual Android UI QA exposed a missing Pending row after picking a text file.
Opening the native picker pauses the Activity. M05 correctly locks its leases,
so the M03 binding captured before the picker becomes stale.

An unprotected owner note now reacquires authority after a nonempty selection,
only when actor, session, canonical identity, content revision, protection and
access revision are identical. Protected notes retain the strict original lease.
The panel reloads the Pending list after a stable picker return. Background lock
and the encrypted draft/binary boundary are retained.

Regression covers stable pause return, changed actor/session/content, denied
authority and canceled selection. This receipt covers source/unit verification;
the rebuilt APK actual UI retest is pending with M04 acceptance.
