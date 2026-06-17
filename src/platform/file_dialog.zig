// Platform-agnostic file dialog facade.
// On Windows, delegates to the Win32 IFileDialog COM backend (win32/file_dialog.zig).
// On other platforms returns error.NotImplemented.
//
// FileFilter and FileDialogOptions are the canonical types; the win32 backend
// imports them from this file to avoid duplicate definitions.

const std     = @import("std");
const builtin = @import("builtin");

pub const FileFilter = struct {
    name: []const u8, // e.g. "PNG Images"
    spec: []const u8, // e.g. "*.png;*.jpg"
};

pub const FileDialogOptions = struct {
    title:       ?[]const u8        = null,
    filters:     []const FileFilter = &.{},
    default_ext: ?[]const u8        = null,
};

/// Show an open-file dialog.
/// Returns the selected path (UTF-8, heap-allocated), or null if the user
/// cancelled.  Returns an error if the OS dialog could not be shown.
/// Caller owns the returned slice and must free it.
pub fn openFile(alloc: std.mem.Allocator, opts: FileDialogOptions) !?[]u8 {
    if (builtin.os.tag == .windows) {
        const backend = @import("win32/file_dialog.zig");
        return backend.openFile(alloc, opts);
    }
    return error.NotImplemented;
}

/// Show a save-file dialog.
/// Returns the selected/typed path (UTF-8, heap-allocated), or null if cancelled.
/// Caller owns the returned slice and must free it.
pub fn saveFile(alloc: std.mem.Allocator, opts: FileDialogOptions) !?[]u8 {
    if (builtin.os.tag == .windows) {
        const backend = @import("win32/file_dialog.zig");
        return backend.saveFile(alloc, opts);
    }
    return error.NotImplemented;
}

/// Show a folder-picker dialog.
/// Returns the selected directory path (UTF-8, heap-allocated), or null if cancelled.
/// Caller owns the returned slice and must free it.
pub fn openFolder(alloc: std.mem.Allocator, title: ?[]const u8) !?[]u8 {
    if (builtin.os.tag == .windows) {
        const backend = @import("win32/file_dialog.zig");
        return backend.openFolder(alloc, title);
    }
    return error.NotImplemented;
}
