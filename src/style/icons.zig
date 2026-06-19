//! Icon codepoints for the "Segoe MDL2 Assets" font (ships on Windows 10 1709+
//! and Windows 11). Each constant is the UTF-8 encoding of a Private Use Area
//! codepoint; pass it to `Renderer.drawIcon`.
//!
//! Reference: https://learn.microsoft.com/windows/apps/design/style/segoe-ui-symbol-font
//!
//!     r.drawIcon(zui.icons.settings, x, y, color, 2);

pub const settings = "\u{E713}"; // gear / cog
pub const back = "\u{E72B}"; // chevron left
pub const forward = "\u{E72A}"; // chevron right
pub const close = "\u{E711}"; // X
pub const accept = "\u{E73E}"; // checkmark
pub const cancel = "\u{E711}"; // X (alias)
pub const play = "\u{E768}";
pub const stop = "\u{E71A}";
pub const video = "\u{E714}"; // video / camera
pub const volume = "\u{E767}"; // speaker
pub const mute = "\u{E74F}"; // muted speaker
pub const people = "\u{E716}"; // contacts
pub const refresh = "\u{E72C}";
pub const fullscreen = "\u{E740}";
pub const home = "\u{E80F}";
