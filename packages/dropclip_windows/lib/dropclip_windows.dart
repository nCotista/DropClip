/// Windows native layer of DropClip (T1.7, FR-03A).
///
/// The plugin serves the PROTO-DC-V2.0 §14.1 clipboard channels on Windows
/// with an event-driven `AddClipboardFormatListener` watcher, and sends
/// `is_concealed: true` without reading content for the §10.4 markers. Talk
/// to it with `NativeClipboard` from `dropclip_clipboard`; macOS serves the
/// same channels from `dropclip_macos` (T1.6).
///
/// Call `start` before `read` / `write` / `clear` (they answer `NOT_STARTED`
/// otherwise). A held clipboard answers `CLIPBOARD_LOCKED`.
library dropclip_windows;

/// `MethodChannel` name: `start`, `stop`, `read`, `write`, `clear`,
/// `changeToken`.
const clipboardMethodChannel = 'dropclip/clipboard';

/// `EventChannel` name: one `ClipSnapshot` map per clipboard change.
const clipboardEventChannel = 'dropclip/clipboard/events';
