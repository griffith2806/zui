// Win32 IFileDialog COM implementation.
// Uses the Vista+ Common Item Dialog (shell32 / ole32) to show open-file,
// save-file, and open-folder dialogs with optional title and file-type filters.
//
// COM vtable pattern follows the convention established in uia.zig:
//   extern struct { vtbl: *const VtblType } — "face" layout, vtbl at offset 0.
//
// Public types (FileFilter, FileDialogOptions) are imported from the platform
// facade (src/platform/file_dialog.zig) to keep a single canonical definition.

const std    = @import("std");
const builtin = @import("builtin");
const facade = @import("../file_dialog.zig");

comptime {
    if (builtin.os.tag != .windows) @compileError("file_dialog win32 backend is Windows-only");
}

// Re-export canonical public types so callers can use either module.
pub const FileFilter      = facade.FileFilter;
pub const FileDialogOptions = facade.FileDialogOptions;

// ── Win32 primitive types ─────────────────────────────────────────────────────

const HWND    = ?*opaque {};
const HRESULT = i32;
const ULONG   = u32;
const DWORD   = u32;
const WCHAR   = u16;
const LPWSTR  = [*:0]WCHAR;
const LPCWSTR = [*:0]const WCHAR;

const winapi = std.builtin.CallingConvention.winapi;

const S_OK:    HRESULT = 0;
// HRESULT_FROM_WIN32(ERROR_CANCELLED) = 0x800704C7
const ERROR_CANCELLED: HRESULT = @as(HRESULT, @bitCast(@as(u32, 0x800704C7)));

// ── GUID ─────────────────────────────────────────────────────────────────────

const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,
};

// IFileDialog  {42F85136-DB7E-439C-85F1-E4075D135FC8}
const IID_IFileDialog = GUID{
    .Data1 = 0x42F85136, .Data2 = 0xDB7E, .Data3 = 0x439C,
    .Data4 = .{ 0x85, 0xF1, 0xE4, 0x07, 0x5D, 0x13, 0x5F, 0xC8 },
};

// IShellItem   {43826D1E-E718-42EE-BC55-A1E261C37BFE}
const IID_IShellItem = GUID{
    .Data1 = 0x43826D1E, .Data2 = 0xE718, .Data3 = 0x42EE,
    .Data4 = .{ 0xBC, 0x55, 0xA1, 0xE2, 0x61, 0xC3, 0x7B, 0xFE },
};

// CLSID_FileOpenDialog  {DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}
const CLSID_FileOpenDialog = GUID{
    .Data1 = 0xDC1C5A9C, .Data2 = 0xE88A, .Data3 = 0x4DDE,
    .Data4 = .{ 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 },
};

// CLSID_FileSaveDialog  {C0B4E2F3-BA21-4773-8DBA-335EC946EB8B}
const CLSID_FileSaveDialog = GUID{
    .Data1 = 0xC0B4E2F3, .Data2 = 0xBA21, .Data3 = 0x4773,
    .Data4 = .{ 0x8D, 0xBA, 0x33, 0x5E, 0xC9, 0x46, 0xEB, 0x8B },
};

// ── COM extern declarations ───────────────────────────────────────────────────

extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: DWORD) callconv(winapi) HRESULT;
extern "ole32" fn CoUninitialize() callconv(winapi) void;
extern "ole32" fn CoCreateInstance(
    rclsid:       *const GUID,
    pUnkOuter:    ?*anyopaque,
    dwClsContext: DWORD,
    riid:         *const GUID,
    ppv:          *?*anyopaque,
) callconv(winapi) HRESULT;
extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(winapi) void;

const CLSCTX_INPROC_SERVER:     DWORD = 0x1;
const COINIT_APARTMENTTHREADED: DWORD = 0x2;

// ── IFileDialog FOS option flags ──────────────────────────────────────────────

const FOS_FORCEFILESYSTEM: DWORD = 0x00000040;
const FOS_PICKFOLDERS:     DWORD = 0x00000020;
const FOS_PATHMUSTEXIST:   DWORD = 0x00000800;
const FOS_FILEMUSTEXIST:   DWORD = 0x00001000;

// SIGDN_FILESYSPATH — return the full file-system path from GetDisplayName.
const SIGDN_FILESYSPATH: u32 = 0x80058000;

// ── COMDLG_FILTERSPEC ────────────────────────────────────────────────────────

const COMDLG_FILTERSPEC = extern struct {
    pszName: LPCWSTR,
    pszSpec: LPCWSTR,
};

// ── COM vtable structs ────────────────────────────────────────────────────────
//
// Layout rule: the first field is always the vtbl pointer, matching the COM ABI.
// We never *implement* these interfaces — we only *call into* them.
// Method slots are listed in strict COM vtable order (IUnknown → IModalWindow
// → IFileDialog / IShellItem).

const IFileDialogVtbl = extern struct {
    // IUnknown (slots 0-2)
    QueryInterface:      *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:              *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:             *const fn (*anyopaque) callconv(winapi) ULONG,
    // IModalWindow (slot 3)
    Show:                *const fn (*anyopaque, HWND) callconv(winapi) HRESULT,
    // IFileDialog (slots 4-29)
    SetFileTypes:        *const fn (*anyopaque, u32, [*]const COMDLG_FILTERSPEC) callconv(winapi) HRESULT,
    SetFileTypeIndex:    *const fn (*anyopaque, u32) callconv(winapi) HRESULT,
    GetFileTypeIndex:    *const fn (*anyopaque, *u32) callconv(winapi) HRESULT,
    Advise:              *const fn (*anyopaque, *anyopaque, *DWORD) callconv(winapi) HRESULT,
    Unadvise:            *const fn (*anyopaque, DWORD) callconv(winapi) HRESULT,
    SetOptions:          *const fn (*anyopaque, DWORD) callconv(winapi) HRESULT,
    GetOptions:          *const fn (*anyopaque, *DWORD) callconv(winapi) HRESULT,
    SetDefaultFolder:    *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    SetFolder:           *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
    GetFolder:           *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetCurrentSelection: *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    SetFileName:         *const fn (*anyopaque, LPCWSTR) callconv(winapi) HRESULT,
    GetFileName:         *const fn (*anyopaque, *LPWSTR) callconv(winapi) HRESULT,
    SetTitle:            *const fn (*anyopaque, LPCWSTR) callconv(winapi) HRESULT,
    SetOkButtonLabel:    *const fn (*anyopaque, LPCWSTR) callconv(winapi) HRESULT,
    SetFileNameLabel:    *const fn (*anyopaque, LPCWSTR) callconv(winapi) HRESULT,
    GetResult:           *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    AddPlace:            *const fn (*anyopaque, *anyopaque, u32) callconv(winapi) HRESULT,
    SetDefaultExtension: *const fn (*anyopaque, LPCWSTR) callconv(winapi) HRESULT,
    Close:               *const fn (*anyopaque, HRESULT) callconv(winapi) HRESULT,
    SetClientGuid:       *const fn (*anyopaque, *const GUID) callconv(winapi) HRESULT,
    ClearClientData:     *const fn (*anyopaque) callconv(winapi) HRESULT,
    SetFilter:           *const fn (*anyopaque, *anyopaque) callconv(winapi) HRESULT,
};

const IShellItemVtbl = extern struct {
    // IUnknown (slots 0-2)
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    AddRef:         *const fn (*anyopaque) callconv(winapi) ULONG,
    Release:        *const fn (*anyopaque) callconv(winapi) ULONG,
    // IShellItem (slots 3-6)
    BindToHandler:  *const fn (*anyopaque, ?*anyopaque, *const GUID, *const GUID, *?*anyopaque) callconv(winapi) HRESULT,
    GetParent:      *const fn (*anyopaque, *?*anyopaque) callconv(winapi) HRESULT,
    GetDisplayName: *const fn (*anyopaque, u32, *LPWSTR) callconv(winapi) HRESULT,
    GetAttributes:  *const fn (*anyopaque, u32, *u32) callconv(winapi) HRESULT,
    Compare:        *const fn (*anyopaque, *anyopaque, u32, *i32) callconv(winapi) HRESULT,
};

// "Face" types — a COM object pointer is a pointer to the vtbl pointer.
const IFileDialogFace = extern struct { vtbl: *const IFileDialogVtbl };
const IShellItemFace  = extern struct { vtbl: *const IShellItemVtbl  };

// ── Internal dialog runner ────────────────────────────────────────────────────

const DialogKind = enum { open_file, save_file, open_folder };

/// Shared implementation for openFile / saveFile / openFolder.
fn runDialog(
    alloc: std.mem.Allocator,
    kind:  DialogKind,
    opts:  FileDialogOptions,
) !?[]u8 {
    // ── 1. CoInitializeEx ────────────────────────────────────────────────────
    // S_OK (0)  = first init on this thread.
    // S_FALSE (1) = already initialised on this thread; still call CoUninitialize.
    // Negative = error.
    const co_hr = CoInitializeEx(null, COINIT_APARTMENTTHREADED);
    if (co_hr < 0) return error.CoInitFailed;
    defer CoUninitialize();

    // ── 2. CoCreateInstance ──────────────────────────────────────────────────
    const clsid: *const GUID = switch (kind) {
        .open_file, .open_folder => &CLSID_FileOpenDialog,
        .save_file               => &CLSID_FileSaveDialog,
    };

    var raw_dialog: ?*anyopaque = null;
    {
        const hr = CoCreateInstance(
            clsid,
            null,
            CLSCTX_INPROC_SERVER,
            &IID_IFileDialog,
            &raw_dialog,
        );
        if (hr != S_OK) return error.CoCreateFailed;
    }
    const face: *IFileDialogFace = @ptrCast(@alignCast(raw_dialog.?));
    defer _ = face.vtbl.Release(@ptrCast(face));

    // ── 3. SetOptions ────────────────────────────────────────────────────────
    var fos: DWORD = FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
    switch (kind) {
        .open_file   => fos |= FOS_FILEMUSTEXIST,
        .open_folder => fos |= FOS_PICKFOLDERS,
        .save_file   => {},
    }
    _ = face.vtbl.SetOptions(@ptrCast(face), fos);

    // ── 4. SetTitle ──────────────────────────────────────────────────────────
    if (opts.title) |t| {
        const title16 = try std.unicode.utf8ToUtf16LeAllocZ(alloc, t);
        defer alloc.free(title16);
        _ = face.vtbl.SetTitle(@ptrCast(face), title16.ptr);
    }

    // ── 5. SetFileTypes / SetDefaultExtension ─────────────────────────────────
    //
    // Keep all wide strings alive until after Show() with an arena.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    if (opts.filters.len > 0) {
        const specs = try aa.alloc(COMDLG_FILTERSPEC, opts.filters.len);
        for (opts.filters, 0..) |f, i| {
            const name16 = try std.unicode.utf8ToUtf16LeAllocZ(aa, f.name);
            const spec16 = try std.unicode.utf8ToUtf16LeAllocZ(aa, f.spec);
            specs[i] = .{ .pszName = name16.ptr, .pszSpec = spec16.ptr };
        }
        _ = face.vtbl.SetFileTypes(@ptrCast(face), @intCast(opts.filters.len), specs.ptr);
    }

    if (opts.default_ext) |ext| {
        const ext16 = try std.unicode.utf8ToUtf16LeAllocZ(aa, ext);
        _ = face.vtbl.SetDefaultExtension(@ptrCast(face), ext16.ptr);
    }

    // ── 6. Show ──────────────────────────────────────────────────────────────
    const show_hr = face.vtbl.Show(@ptrCast(face), null);
    if (show_hr == ERROR_CANCELLED) return null;
    if (show_hr != S_OK) return error.DialogShowFailed;

    // ── 7. GetResult → IShellItem ────────────────────────────────────────────
    var raw_item: ?*anyopaque = null;
    {
        const hr = face.vtbl.GetResult(@ptrCast(face), &raw_item);
        if (hr != S_OK) return error.GetResultFailed;
    }
    const item: *IShellItemFace = @ptrCast(@alignCast(raw_item.?));
    defer _ = item.vtbl.Release(@ptrCast(item));

    // ── 8. GetDisplayName(SIGDN_FILESYSPATH) ─────────────────────────────────
    var path_ptr: LPWSTR = undefined;
    {
        const hr = item.vtbl.GetDisplayName(@ptrCast(item), SIGDN_FILESYSPATH, &path_ptr);
        if (hr != S_OK) return error.GetDisplayNameFailed;
    }
    defer CoTaskMemFree(path_ptr);

    // ── 9. Convert UTF-16 → UTF-8 with caller's allocator ────────────────────
    const wide_len = std.mem.len(path_ptr);
    return try std.unicode.utf16LeToUtf8Alloc(alloc, path_ptr[0..wide_len]);
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Show an open-file dialog.  Returns null if cancelled.  Caller owns slice.
pub fn openFile(alloc: std.mem.Allocator, opts: FileDialogOptions) !?[]u8 {
    return runDialog(alloc, .open_file, opts);
}

/// Show a save-file dialog.  Returns null if cancelled.  Caller owns slice.
pub fn saveFile(alloc: std.mem.Allocator, opts: FileDialogOptions) !?[]u8 {
    return runDialog(alloc, .save_file, opts);
}

/// Show a folder-picker dialog.  Returns null if cancelled.  Caller owns slice.
pub fn openFolder(alloc: std.mem.Allocator, title: ?[]const u8) !?[]u8 {
    return runDialog(alloc, .open_folder, .{ .title = title });
}
