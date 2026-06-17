# File Dialogs Progress

## Status: Complete

### Done
- Studied COM vtable pattern from `src/platform/win32/uia.zig`
- Studied UTF-16 conversion patterns from `src/platform/win32/clipboard.zig`
- Verified `std.unicode.utf8ToUtf16LeAllocZ` and `utf16LeToUtf8Alloc` signatures in Zig 0.16 std
- Created `src/platform/win32/file_dialog.zig` — IFileDialog COM implementation
  - IFileDialogVtbl / IShellItemVtbl extern structs (full vtable slot order)
  - CoInitializeEx / CoUninitialize / CoCreateInstance / CoTaskMemFree via `extern "ole32"`
  - Arena allocator keeps wide-char strings alive across Show()
  - Handles ERROR_CANCELLED → null return
  - openFile, saveFile, openFolder all delegate to runDialog()
- Created `src/platform/file_dialog.zig` — platform-agnostic facade
  - FileFilter, FileDialogOptions canonical type definitions live here
  - win32 backend imported inside `if (builtin.os.tag == .windows)` branches
  - Non-Windows paths return `error.NotImplemented`
- Updated `src/root.zig` — exports FileFilter, FileDialogOptions, openFile, saveFile, openFolder
- `zig build` passes with no errors
- `zig build test` passes with no errors

### In Progress
- (none)

### Blocked
- (none)

### Up Next
- Optional: runtime manual validation — call openFile() from a demo button and confirm the dialog opens
