# UI43 Profile adaptation

## Reference boundary

The current direct Notion Web observation has no like-for-like Profile workflow. This is an adaptation of its quiet white surface, muted supporting text, light hierarchy, and restrained primary action to NoteFlow's existing avatar and display-name controls. It does not claim Profile parity or contribute a similarity score. Android comparison and the overall Web/Android similarity gates remain unverified.

## Change

- Keep the current avatar, display-name, save, reload, and status behavior.
- Stack the avatar preview above its existing actions below the established compact-width breakpoint. This avoids compressing the action labels beside a fixed-width avatar on a phone.
- Place retry/reload below its message on compact layouts and whenever the user's text scale is increased. Keep the live-region announcement and the same enabled/disabled callbacks.
- Keep the Profile body in its existing safe-area scroll view so the focused field and submit action can move above the keyboard.

No fields, actions, callbacks, services, or account behavior were added or changed.

## Scoped checks added

`test/presentation/ui43/profile43_test.dart` covers a narrow, 2x text-scale viewport with a simulated keyboard inset. It checks that avatar actions stack, the name field and submit button can scroll above the inset, and a conflict message keeps its reload action below the message without a layout exception.

The parent owns test execution, analysis, builds, and live Web/Android review. These checks have not been run by this worker.
