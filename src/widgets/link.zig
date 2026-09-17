const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const Signal     = @import("../signals/signal.zig").Signal;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Link = struct {
    text: []const u8,
    color: Color = Color.rgb(0, 120, 212),
    hovered: bool = false,
    clicked: Signal(void) = .{},

    pub fn deinit(self: *Link, alloc: std.mem.Allocator) void {
        self.clicked.deinit(alloc);
    }

    pub fn draw(self: *const Link, r: *Renderer, rect: Rect) void {
        r.drawText(self.text, rect.x, rect.y, self.color);
        if (self.hovered) {
            const tw = r.textWidth(self.text);
            r.fillRect(Rect.init(rect.x, rect.y + 16, tw, 1), self.color);
        }
    }

    pub fn preferredSize(self: *const Link, r: *const Renderer) Size {
        return .{ .width = r.textWidth(self.text), .height = 18 };
    }

    pub fn handleEvent(self: *Link, event: Event, rect: Rect) bool {
        switch (event) {
            .mouse_move => |m| {
                self.hovered = rect.contains(.{ .x = m.x, .y = m.y });
                return false;
            },
            .mouse_release => |m| {
                if (rect.contains(.{ .x = m.x, .y = m.y })) {
                    self.clicked.emit({});
                    return true;
                }
            },
            else => {},
        }
        return false;
    }

    pub fn accessNode(self: *Link, rect: Rect, focused: bool) AccessNode {
        return .{
            .role   = .link,
            .name   = self.text,
            .bounds = rect,
            .state  = .{ .focused = focused, .enabled = true },
            .invoke_fn = struct {
                fn f(ctx: *anyopaque) void {
                    const l: *Link = @ptrCast(@alignCast(ctx));
                    l.clicked.emit({});
                }
            }.f,
            .ctx = self,
        };
    }
};

test "Link handleEvent hovers and emits clicked" {
    const alloc = std.testing.allocator;
    var link = Link{ .text = "Docs" };
    defer link.deinit(alloc);

    var hits: u32 = 0;
    _ = try link.clicked.connect(alloc, &hits, struct {
        fn f(p: *u32, _: void) void { p.* += 1; }
    }.f);

    const rect = Rect.init(0, 0, 60, 18);
    _ = link.handleEvent(.{ .mouse_move = .{ .x = 5, .y = 5, .dx = 0, .dy = 0 } }, rect);
    try std.testing.expect(link.hovered);
    _ = link.handleEvent(.{ .mouse_move = .{ .x = 500, .y = 5, .dx = 0, .dy = 0 } }, rect);
    try std.testing.expect(!link.hovered);

    const handled = link.handleEvent(.{ .mouse_release = .{ .x = 5, .y = 5, .button = .left } }, rect);
    try std.testing.expect(handled);
    try std.testing.expectEqual(@as(u32, 1), hits);
}

test "Link accessNode wires an invoke callback" {
    var link = Link{ .text = "Home" };
    const node = link.accessNode(Rect.init(0, 0, 40, 18), false);
    try std.testing.expectEqual(.link, node.role);
    try std.testing.expectEqualStrings("Home", node.name);
    try std.testing.expect(node.invoke_fn != null);
    try std.testing.expect(node.ctx != null);
}
