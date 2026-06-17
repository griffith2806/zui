const std = @import("std");
const Style = @import("style.zig").Style;

/// Maximum number of pseudo-states we track overrides for.
/// One slot per named flag (hover/focus/disabled/active/checked).
pub const max_pseudo_states: usize = 5;

/// Index constants that parallel the PseudoState bit positions.
pub const IDX_HOVER:    usize = 0;
pub const IDX_FOCUS:    usize = 1;
pub const IDX_DISABLED: usize = 2;
pub const IDX_ACTIVE:   usize = 3;
pub const IDX_CHECKED:  usize = 4;

/// Named tags for the five pseudo-states — used as array indices via setOverride/getOverride.
pub const PseudoStateTag = enum(usize) {
    hover    = IDX_HOVER,
    focus    = IDX_FOCUS,
    disabled = IDX_DISABLED,
    active   = IDX_ACTIVE,
    checked  = IDX_CHECKED,
};

/// Bit-flags for widget pseudo-states, packed into a single `u8`.
///
/// Multiple flags can be active simultaneously (e.g. `.hover` and `.focus`).
///
/// Example:
/// ```zig
/// const ps = PseudoState{ .hover = true, .focus = true };
/// ```
pub const PseudoState = packed struct(u8) {
    hover:    bool = false,
    focus:    bool = false,
    disabled: bool = false,
    active:   bool = false,
    checked:  bool = false,
    _pad:     u3   = 0,

    /// Return the `u8` backing value.
    pub fn bits(self: PseudoState) u8 {
        return @bitCast(self);
    }

    /// Return true when no flag is set.
    pub fn isDefault(self: PseudoState) bool {
        return self.bits() == 0;
    }
};

/// A `WidgetStylesheet` holds a base `Style` plus per-pseudo-state `Style`
/// overrides — all without any allocations.
///
/// **Resolution order** (later wins):
///   base → hover → focus → active → disabled → checked
///
/// `disabled` intentionally overrides `hover` so a disabled widget cannot
/// accidentally appear interactive.
///
/// Usage:
/// ```zig
/// var ss = WidgetStylesheet{};
/// ss.base = Style{ .bg = Color.rgb(45, 45, 48) };
/// ss.setOverride(.hover,    Style{ .bg = Color.rgb(62, 62, 66) });
/// ss.setOverride(.disabled, Style{ .bg = Color.rgb(28, 28, 28), .fg = Color.rgb(100,100,100) });
///
/// const current: Style = ss.resolve(.{ .hover = true });
/// ```
pub const WidgetStylesheet = struct {
    base: Style = .{},
    /// Indexed by IDX_* constants.  `null` means "no override for this state."
    overrides: [max_pseudo_states]?Style = [_]?Style{null} ** max_pseudo_states,

    /// Store a style override for a single named pseudo-state.
    pub fn setOverride(self: *WidgetStylesheet, which: PseudoStateTag, style: Style) void {
        self.overrides[@intFromEnum(which)] = style;
    }

    /// Retrieve the override for a single named pseudo-state, or null if unset.
    pub fn getOverride(self: *const WidgetStylesheet, which: PseudoStateTag) ?Style {
        return self.overrides[@intFromEnum(which)];
    }

    /// Resolve the effective `Style` for the given combined pseudo-state.
    ///
    /// Application order (each non-null override is merged on top of the
    /// accumulated result in this fixed priority order):
    ///   base → hover → focus → active → disabled → checked
    ///
    /// Because `disabled` is applied after `hover`, a disabled widget's
    /// disabled-override wins even if `hover` is also set.
    pub fn resolve(self: *const WidgetStylesheet, pseudo: PseudoState) Style {
        var result = self.base;

        if (pseudo.hover)
            if (self.overrides[IDX_HOVER]) |ov| { result = result.merge(ov); };
        if (pseudo.focus)
            if (self.overrides[IDX_FOCUS]) |ov| { result = result.merge(ov); };
        if (pseudo.active)
            if (self.overrides[IDX_ACTIVE]) |ov| { result = result.merge(ov); };
        if (pseudo.disabled)
            if (self.overrides[IDX_DISABLED]) |ov| { result = result.merge(ov); };
        if (pseudo.checked)
            if (self.overrides[IDX_CHECKED]) |ov| { result = result.merge(ov); };

        return result;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const Color = @import("color.zig").Color;

test "PseudoState: bits and isDefault" {
    const ps = PseudoState{ .hover = true };
    try std.testing.expect(!ps.isDefault());
    try std.testing.expectEqual(@as(u8, 1), ps.bits());

    const none = PseudoState{};
    try std.testing.expect(none.isDefault());
    try std.testing.expectEqual(@as(u8, 0), none.bits());
}

test "PseudoState: multiple flags" {
    const ps = PseudoState{ .hover = true, .focus = true };
    // bit 0 = hover, bit 1 = focus  =>  0b0000_0011 = 3
    try std.testing.expectEqual(@as(u8, 0b0000_0011), ps.bits());
}

test "WidgetStylesheet.resolve: base only" {
    const bg = Color.rgb(10, 20, 30);
    const ss = WidgetStylesheet{ .base = Style{ .bg = bg } };
    const result = ss.resolve(.{});
    try std.testing.expectEqual(bg, result.bg.?);
}

test "WidgetStylesheet.resolve: hover override" {
    const base_bg  = Color.rgb(45, 45, 48);
    const hover_bg = Color.rgb(62, 62, 66);

    var ss = WidgetStylesheet{ .base = Style{ .bg = base_bg } };
    ss.setOverride(.hover, Style{ .bg = hover_bg });

    // No hover -> base
    const plain = ss.resolve(.{});
    try std.testing.expectEqual(base_bg, plain.bg.?);

    // Hover active -> override
    const hovered = ss.resolve(.{ .hover = true });
    try std.testing.expectEqual(hover_bg, hovered.bg.?);
}

test "WidgetStylesheet.resolve: disabled overrides hover" {
    const base_bg     = Color.rgb(45, 45, 48);
    const hover_bg    = Color.rgb(62, 62, 66);
    const disabled_bg = Color.rgb(28, 28, 28);

    var ss = WidgetStylesheet{ .base = Style{ .bg = base_bg } };
    ss.setOverride(.hover,    Style{ .bg = hover_bg });
    ss.setOverride(.disabled, Style{ .bg = disabled_bg });

    // Both hover and disabled active -- disabled must win
    const result = ss.resolve(.{ .hover = true, .disabled = true });
    try std.testing.expectEqual(disabled_bg, result.bg.?);
}

test "WidgetStylesheet.resolve: partial override merges correctly" {
    const fg = Color.white;
    const hover_bg = Color.rgb(80, 80, 80);

    var ss = WidgetStylesheet{
        .base = Style{ .fg = fg, .bg = Color.black },
    };
    ss.setOverride(.hover, Style{ .bg = hover_bg }); // hover only overrides bg

    const result = ss.resolve(.{ .hover = true });
    try std.testing.expectEqual(hover_bg, result.bg.?);
    try std.testing.expectEqual(fg, result.fg.?); // fg inherited from base
}

test "WidgetStylesheet: getOverride returns null when unset" {
    const ss = WidgetStylesheet{};
    try std.testing.expectEqual(@as(?Style, null), ss.getOverride(.focus));
}

test "WidgetStylesheet.resolve: active overrides hover, disabled overrides active" {
    const base_bg    = Color.rgb(45, 45, 48);
    const hover_bg   = Color.rgb(62, 62, 66);
    const active_bg  = Color.rgb(28, 28, 28);
    const disabled_bg = Color.rgb(15, 15, 15);

    var ss = WidgetStylesheet{ .base = Style{ .bg = base_bg } };
    ss.setOverride(.hover,    Style{ .bg = hover_bg });
    ss.setOverride(.active,   Style{ .bg = active_bg });
    ss.setOverride(.disabled, Style{ .bg = disabled_bg });

    // hover + active -> active wins (applied later)
    const pressed = ss.resolve(.{ .hover = true, .active = true });
    try std.testing.expectEqual(active_bg, pressed.bg.?);

    // hover + active + disabled -> disabled wins
    const all = ss.resolve(.{ .hover = true, .active = true, .disabled = true });
    try std.testing.expectEqual(disabled_bg, all.bg.?);
}
