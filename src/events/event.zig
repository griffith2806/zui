const std = @import("std");

pub const MouseButton = enum { left, middle, right, x1, x2 };

pub const KeyCode = enum {
    a, b, c, d, e, f, g, h, i, j, k, l, m,
    n, o, p, q, r, s, t, u, v, w, x, y, z,
    @"0", @"1", @"2", @"3", @"4",
    @"5", @"6", @"7", @"8", @"9",
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    up, down, left, right,
    enter, escape, backspace, tab, space, delete, insert,
    home, end, page_up, page_down,
    left_shift, right_shift,
    left_ctrl, right_ctrl,
    left_alt, right_alt,
    left_super, right_super,
    unknown,
};

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    _pad: u4 = 0,
};

pub const MouseEvent = struct {
    x: i32,
    y: i32,
    button: MouseButton,
    modifiers: Modifiers = .{},
};

pub const MouseMoveEvent = struct {
    x: i32,
    y: i32,
    dx: i32,
    dy: i32,
    modifiers: Modifiers = .{},
};

pub const KeyEvent = struct {
    key: KeyCode,
    modifiers: Modifiers = .{},
    repeat: bool = false,
};

pub const ResizeEvent = struct {
    width: u32,
    height: u32,
};

pub const ScrollEvent = struct {
    x: i32,
    y: i32,
    dx: f32,
    dy: f32,
};

/// Payload for an in-progress IME composition string update.
/// Stored inline (no heap allocation); 192 bytes fits up to 64 CJK characters.
pub const IME_BUF_MAX = 192;

pub const ImeCompositionEvent = struct {
    buf: [IME_BUF_MAX]u8 = undefined,
    len: usize           = 0,

    pub fn text(self: *const ImeCompositionEvent) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn fromSlice(src: []const u8) ImeCompositionEvent {
        var ev = ImeCompositionEvent{};
        const n = @min(src.len, IME_BUF_MAX);
        @memcpy(ev.buf[0..n], src[0..n]);
        ev.len = n;
        return ev;
    }
};

/// Payload delivered on `drag_enter` and `drop` events.
/// Memory is owned by the platform's DropTarget arena — do not hold across event loop iterations.
pub const DragPayload = struct {
    files: []const []const u8,
    text: []const u8,
    x: i32,
    y: i32,
};

/// Position-only payload delivered on `drag_over`.
pub const DragPosition = struct { x: i32, y: i32 };

pub const Event = union(enum) {
    mouse_press: MouseEvent,
    mouse_release: MouseEvent,
    mouse_move: MouseMoveEvent,
    key_press: KeyEvent,
    key_release: KeyEvent,
    char_input: u21,
    /// IME session is beginning — widget can prepare composition display.
    ime_start: void,
    /// IME composition update — `text` is the provisional (uncommitted) string.
    ime_composition: ImeCompositionEvent,
    /// IME session ended (committed via char_input or cancelled via Escape).
    ime_cancel: void,
    resize: ResizeEvent,
    scroll: ScrollEvent,
    close: void,
    paint: void,
    focus_gained: void,
    focus_lost: void,
    /// A dragged object entered the window. `DragPayload.files` and `.text`
    /// are populated with a preview of what will be dropped.
    drag_enter: DragPayload,
    /// The drag cursor moved while hovering over the window.
    drag_over: DragPosition,
    /// The drag left the window without a drop.
    drag_leave: void,
    /// The user released the mouse and completed a drop into the window.
    drop: DragPayload,
};

test "MouseEvent field access" {
    const ev = MouseEvent{ .x = 10, .y = 20, .button = .left };
    try std.testing.expectEqual(@as(i32, 10), ev.x);
    try std.testing.expectEqual(@as(i32, 20), ev.y);
    try std.testing.expectEqual(MouseButton.left, ev.button);
}

test "Event union switch" {
    const ev = Event{ .key_press = .{ .key = .enter, .repeat = false } };
    switch (ev) {
        .key_press => |k| try std.testing.expectEqual(KeyCode.enter, k.key),
        else => return error.WrongVariant,
    }
}

test "Modifiers default" {
    const mods = Modifiers{};
    try std.testing.expect(!mods.shift);
    try std.testing.expect(!mods.ctrl);
}

test "DragPayload fields" {
    const payload = DragPayload{
        .files = &.{},
        .text  = "",
        .x     = 100,
        .y     = 200,
    };
    try std.testing.expectEqual(@as(usize, 0), payload.files.len);
    try std.testing.expectEqual(@as(i32, 100), payload.x);
}
