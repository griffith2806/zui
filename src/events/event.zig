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

pub const ImeComposition = struct {
    /// The in-progress candidate string (UTF-8, heap-allocated, caller must free)
    composition: []const u8,
    /// The cursor position within the composition string (byte offset)
    cursor: usize,
    /// True when GCS_RESULTSTR is set — the composition is committed
    committed: bool,
};

pub const Event = union(enum) {
    mouse_press: MouseEvent,
    mouse_release: MouseEvent,
    mouse_move: MouseMoveEvent,
    key_press: KeyEvent,
    key_release: KeyEvent,
    char_input: u21,
    resize: ResizeEvent,
    scroll: ScrollEvent,
    close: void,
    paint: void,
    focus_gained: void,
    focus_lost: void,
    ime_start: void,
    ime_composition: ImeComposition,
    ime_end: void,
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
