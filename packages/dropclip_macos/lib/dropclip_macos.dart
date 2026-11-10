/// macOS native layer of DropClip (T1.6, FR-03A).
///
/// The plugin serves the PROTO-DC-V2.0 §14.1 clipboard channels on macOS:
/// `NSPasteboard` `changeCount` polling at 200 / 1,000 / 2,000 ms
/// (active / idle / screen locked), and `is_concealed: true` without reading
/// content for the §10.4 markers. Talk to it with `NativeClipboard` from
/// `dropclip_clipboard`; the Windows runner serves the same channels (T1.7).
library dropclip_macos;

/// `MethodChannel` name: `start`, `stop`, `read`, `write`, `clear`,
/// `changeToken`.
const clipboardMethodChannel = 'dropclip/clipboard';

/// `EventChannel` name: one `ClipSnapshot` map per pasteboard change.
const clipboardEventChannel = 'dropclip/clipboard/events';
