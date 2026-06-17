# IME/CJK Input Progress

## Status: Complete

### Done
- Added `ImeComposition` struct and three new `Event` variants (`ime_start`, `ime_composition`, `ime_end`) to `src/events/event.zig`
- Added Win32 IME message handling in `src/platform/win32/window.zig`:
  - Declared `HIMC` opaque type and `ImmGetContext`, `ImmReleaseContext`, `ImmGetCompositionStringW` via `extern "imm32"`
  - Added `WM_IME_STARTCOMPOSITION`, `WM_IME_ENDCOMPOSITION`, `WM_IME_COMPOSITION` constants and `GCS_COMPSTR` / `GCS_RESULTSTR` flags
  - `WM_IME_STARTCOMPOSITION` → emits `Event{ .ime_start = {} }`
  - `WM_IME_ENDCOMPOSITION` → frees composition buffer, emits `Event{ .ime_end = {} }`
  - `WM_IME_COMPOSITION` with `GCS_RESULTSTR` → walks UTF-16LE buffer, emits each codepoint as `char_input`, then emits `ime_end`
  - `WM_IME_COMPOSITION` with `GCS_COMPSTR` → converts UTF-16LE → UTF-8 via `std.unicode.utf16LeToUtf8Alloc`, stores in `Window.ime_buf`, emits `ime_composition`
  - Added `alloc: std.mem.Allocator` and `ime_buf: ?[]u8` fields to `Window` struct; `ime_buf` freed in `deinit`
- Added `imm32` system library link in `build.zig` (Windows only)
- Updated `src/widgets/text_field.zig`:
  - Added `ime_active: bool` and `composition: []const u8` fields (composition NOT owned by TextField)
  - `ime_start` handler sets `ime_active = true`, clears composition
  - `ime_composition` handler stores the candidate string slice
  - `ime_end` handler clears both fields
  - `draw()` renders composition string in dimmed color with a 1px underline after the cursor when `ime_active`; hides the normal cursor bar during composition
- Updated `docs/API.md` with `ImeComposition` type, new Event variants, TextField IME fields, and usage notes

### Blocked
- (none)

### Up Next
- Cursor position within composition string (currently always placed at end; would need `ImmGetCompositionStringW` with `GCS_CURSORPOS` index)
- TextArea IME support (mirrors TextField pattern)
