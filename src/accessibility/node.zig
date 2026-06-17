const Rect = @import("../layout/geometry.zig").Rect;

pub const Role = enum {
    window,
    button,
    label,
    text_field,
    text_area,
    checkbox,
    slider,
    progress_bar,
    tab,
    tab_panel,
    list,
    list_item,
    combo_box,
    menu,
    menu_item,
    scroll_area,
    container,
    separator,
    group,
};

pub const State = struct {
    focused:   bool = false,
    enabled:   bool = true,
    checked:   bool = false,
    expanded:  bool = false,
    selected:  bool = false,
    read_only: bool = false,
};

/// Platform-agnostic description of one UI element for assistive technologies.
/// `bounds` are logical (device-independent) pixels in window-client coordinates.
/// `name` and `value` are UTF-8 slices that must outlive the node.
///
/// Optional action callbacks let UIA patterns invoke real widget behaviour.
/// All callback fields default to null so existing code requires no changes.
pub const AccessNode = struct {
    role:      Role,
    name:      []const u8,
    value:     []const u8 = "",
    bounds:    Rect,
    state:     State = .{},
    /// Called by IInvokeProvider.Invoke() — typically emits a clicked signal.
    invoke_fn: ?*const fn (ctx: *anyopaque) void = null,
    /// Called by IToggleProvider.Toggle() — should flip the checked state.
    toggle_fn: ?*const fn (ctx: *anyopaque) void = null,
    /// Opaque pointer passed to invoke_fn / toggle_fn.
    ctx:       ?*anyopaque = null,
};
