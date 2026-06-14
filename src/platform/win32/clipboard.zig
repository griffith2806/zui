const std = @import("std");

const HWND   = *opaque {};
const HANDLE = *anyopaque;
const HGLOBAL = *anyopaque;
const BOOL   = i32;
const UINT   = u32;
const SIZE_T = usize;

const CF_UNICODETEXT: UINT = 13;
const GMEM_MOVEABLE:  UINT = 0x0002;

extern "user32"  fn OpenClipboard(hWnd: ?HWND) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32"  fn CloseClipboard() callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32"  fn EmptyClipboard() callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "user32"  fn GetClipboardData(uFormat: UINT) callconv(std.builtin.CallingConvention.winapi) ?HGLOBAL;
extern "user32"  fn SetClipboardData(uFormat: UINT, hMem: ?HGLOBAL) callconv(std.builtin.CallingConvention.winapi) ?HGLOBAL;
extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: SIZE_T) callconv(std.builtin.CallingConvention.winapi) ?HGLOBAL;
extern "kernel32" fn GlobalLock(hMem: HGLOBAL) callconv(std.builtin.CallingConvention.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: HGLOBAL) callconv(std.builtin.CallingConvention.winapi) BOOL;
extern "kernel32" fn GlobalSize(hMem: HGLOBAL) callconv(std.builtin.CallingConvention.winapi) SIZE_T;

/// Write UTF-8 text to the Windows clipboard.
pub fn setText(text: []const u8, alloc: std.mem.Allocator) void {
    const wide = std.unicode.utf8ToUtf16LeAlloc(alloc, text) catch return;
    defer alloc.free(wide);

    const byte_len = (wide.len + 1) * @sizeOf(u16);
    const hmem = GlobalAlloc(GMEM_MOVEABLE, byte_len) orelse return;
    const ptr: [*]u16 = @ptrCast(@alignCast(GlobalLock(hmem) orelse return));
    @memcpy(ptr[0..wide.len], wide);
    ptr[wide.len] = 0;
    _ = GlobalUnlock(hmem);

    if (OpenClipboard(null) == 0) return;
    _ = EmptyClipboard();
    _ = SetClipboardData(CF_UNICODETEXT, hmem);
    _ = CloseClipboard();
}

/// Read UTF-8 text from the Windows clipboard.  Caller owns the returned slice.
pub fn getText(alloc: std.mem.Allocator) ?[]u8 {
    if (OpenClipboard(null) == 0) return null;
    defer _ = CloseClipboard();

    const hmem = GetClipboardData(CF_UNICODETEXT) orelse return null;
    const ptr: [*:0]const u16 = @ptrCast(@alignCast(GlobalLock(hmem) orelse return null));
    defer _ = GlobalUnlock(hmem);

    const wide_len = std.mem.len(ptr);
    const utf8 = std.unicode.utf16LeToUtf8Alloc(alloc, ptr[0..wide_len]) catch return null;
    return utf8;
}
