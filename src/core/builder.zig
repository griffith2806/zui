/// Declarative comptime widget-tree builder for zui.
///
/// Usage:
///
///     const tree = zui.ui(.vbox, .{});
///     const btn  = zui.ui(.button, .{ .label = "Click me" });
///     const lbl  = zui.ui(.label,  .{ .text  = "Hello" });
///
/// The `ui()` function maps a `WidgetTag` to the corresponding widget or layout
/// struct and initialises it from an anonymous struct literal.  Field names in
/// `opts` must match the public fields of the target type; extra fields that
/// exist in `opts` but not in the target type are silently ignored (useful for
/// DSL sugar such as a `children` key on container tags).
///
/// Because `opts` is resolved at comptime via `anytype`, and every field copy
/// is a comptime-known assignment, the builder adds zero runtime cost.

const std = @import("std");

const Button      = @import("../widgets/button.zig").Button;
const ButtonStyle = @import("../widgets/button.zig").ButtonStyle;
const Label       = @import("../widgets/label.zig").Label;
const TextField   = @import("../widgets/text_field.zig").TextField;
const Checkbox    = @import("../widgets/checkbox.zig").Checkbox;
const ListView    = @import("../widgets/list_view.zig").ListView;
const BoxLayout   = @import("../layout/box.zig").BoxLayout;
const Direction   = @import("../layout/box.zig").Direction;

// ── Widget tag ────────────────────────────────────────────────────────────────

/// All widget/layout kinds the builder understands.
pub const WidgetTag = enum {
    button,
    label,
    text_field,
    checkbox,
    list_view,
    hbox,
    vbox,
};

// ── Tag → type mapping ────────────────────────────────────────────────────────

/// Returns the concrete struct type for a given `WidgetTag`.
pub fn WidgetType(comptime tag: WidgetTag) type {
    return switch (tag) {
        .button     => Button,
        .label      => Label,
        .text_field => TextField,
        .checkbox   => Checkbox,
        .list_view  => ListView,
        .hbox, .vbox => BoxLayout,
    };
}

// ── Builder function ──────────────────────────────────────────────────────────

/// Construct a widget from a tag and an anonymous options struct.
///
/// Field names in `opts` that exist in the target struct are copied over;
/// unrecognised fields (e.g. `children`) are silently ignored.  Required
/// fields that have no default in the target struct (e.g. `Button.label`)
/// **must** be present in `opts` — the compiler will emit a clear error if
/// they are missing.
///
/// For `hbox` / `vbox`, the returned `BoxLayout` has its `.direction` preset
/// automatically; you do not need to pass `.direction` in `opts`.
pub fn ui(comptime tag: WidgetTag, opts: anytype) WidgetType(tag) {
    return buildFrom(WidgetType(tag), tag, opts);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

fn hasField(comptime T: type, comptime name: []const u8) bool {
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (comptime std.mem.eql(u8, f.name, name)) return true;
    }
    return false;
}

/// Build a value of type T by:
///   1. For each field in T:
///      a. If opts contains that field (and it isn't the DSL-only `children`
///         key), use the opts value.
///      b. Otherwise, if the field has a default value, use the default.
///      c. Otherwise leave `undefined` (the compiler will catch any use).
///   2. For `hbox`/`vbox`, override `.direction` after the field loop so the
///      correct direction is always set regardless of what opts says.
fn buildFrom(comptime T: type, comptime tag: WidgetTag, opts: anytype) T {
    const OptsType = @TypeOf(opts);
    var out: T = undefined;

    inline for (@typeInfo(T).@"struct".fields) |f| {
        const in_opts = comptime hasField(OptsType, f.name) and
                        !std.mem.eql(u8, f.name, "children");
        if (comptime in_opts) {
            @field(out, f.name) = @field(opts, f.name);
        } else if (comptime f.default_value_ptr != null) {
            @field(out, f.name) = @as(*const f.type, @ptrCast(@alignCast(f.default_value_ptr.?))).*;
        }
        // else: left undefined — required fields without defaults must be in opts
    }

    // Apply direction preset for hbox/vbox; this wins over any `direction`
    // the caller might have passed in opts.
    switch (tag) {
        .hbox => out.direction = .horizontal,
        .vbox => out.direction = .vertical,
        else  => {},
    }

    return out;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "ui button basic" {
    const btn = ui(.button, .{ .label = "Click me" });
    try std.testing.expectEqualStrings("Click me", btn.label);
    // Style should be the ButtonStyle default.
    try std.testing.expectEqual(@as(u32, 6), btn.style.radius);
    try std.testing.expectEqual(false, btn.pressed);
    try std.testing.expectEqual(false, btn.hovered);
}

test "ui button with style override" {
    const s = ButtonStyle{ .radius = 12 };
    const btn = ui(.button, .{ .label = "OK", .style = s });
    try std.testing.expectEqualStrings("OK", btn.label);
    try std.testing.expectEqual(@as(u32, 12), btn.style.radius);
}

test "ui label" {
    const lbl = ui(.label, .{ .text = "Hello, zui!" });
    try std.testing.expectEqualStrings("Hello, zui!", lbl.text);
}

test "ui vbox direction preset" {
    const vb = ui(.vbox, .{});
    try std.testing.expectEqual(Direction.vertical, vb.direction);
}

test "ui hbox direction preset" {
    const hb = ui(.hbox, .{});
    try std.testing.expectEqual(Direction.horizontal, hb.direction);
}

test "ui hbox with spacing" {
    const hb = ui(.hbox, .{ .spacing = 16 });
    try std.testing.expectEqual(Direction.horizontal, hb.direction);
    try std.testing.expectEqual(@as(u32, 16), hb.spacing);
}

test "ui children field is ignored" {
    // Passing a `children` field must not cause a compile error even though
    // BoxLayout has no such field.
    const vb = ui(.vbox, .{ .spacing = 4, .children = .{} });
    try std.testing.expectEqual(@as(u32, 4), vb.spacing);
    try std.testing.expectEqual(Direction.vertical, vb.direction);
}
