const std      = @import("std");
const Color    = @import("../style/color.zig").Color;
const Rect     = @import("../layout/geometry.zig").Rect;
const Size     = @import("../layout/geometry.zig").Size;
const Point    = @import("../layout/geometry.zig").Point;
const Renderer = @import("../graphics/renderer.zig").Renderer;
const Event    = @import("../events/event.zig").Event;

pub const ScrollArea = struct {
    content_height:    u32   = 0,
    scroll_offset:     i32   = 0,
    scrollbar_width:   u32   = 12,
    track_color:       Color = Color.rgba(255, 255, 255, 15),
    thumb_color:       Color = Color.rgba(255, 255, 255, 80),
    thumb_hover_color: Color = Color.rgba(255, 255, 255, 120),
    line_height:       u32   = 20,
    dragging:          bool  = false,
    drag_start_y:      i32   = 0,
    drag_start_offset: i32   = 0,
    thumb_hovered:     bool  = false,

    pub fn contentRect(self: *const ScrollArea, rect: Rect) Rect {
        return Rect.init(rect.x, rect.y, rect.width -| self.scrollbar_width, rect.height);
    }

    pub fn trackRect(self: *const ScrollArea, rect: Rect) Rect {
        return Rect.init(
            rect.right() - @as(i32, @intCast(self.scrollbar_width)),
            rect.y,
            self.scrollbar_width,
            rect.height,
        );
    }

    pub fn thumbRect(self: *const ScrollArea, rect: Rect) ?Rect {
        if (self.content_height <= rect.height) return null;

        const visible_ratio = @as(f32, @floatFromInt(rect.height)) /
            @as(f32, @floatFromInt(self.content_height));
        const thumb_h = @max(20, @as(u32, @intFromFloat(
            @as(f32, @floatFromInt(rect.height)) * visible_ratio,
        )));

        const max = self.maxOffset(rect);
        const scroll_ratio = @as(f32, @floatFromInt(self.scroll_offset)) /
            @as(f32, @floatFromInt(max));
        const thumb_y = rect.y + @as(i32, @intFromFloat(
            @as(f32, @floatFromInt(rect.height -| thumb_h)) * scroll_ratio,
        ));

        const track = self.trackRect(rect);
        return Rect.init(track.x + 2, thumb_y, self.scrollbar_width -| 4, thumb_h);
    }

    fn maxOffset(self: *const ScrollArea, rect: Rect) i32 {
        const raw = @as(i32, @intCast(self.content_height)) - @as(i32, @intCast(rect.height));
        return if (raw > 0) raw else 0;
    }

    pub fn clampOffset(self: *ScrollArea, rect: Rect) void {
        const max = self.maxOffset(rect);
        if (self.scroll_offset < 0) self.scroll_offset = 0;
        if (self.scroll_offset > max) self.scroll_offset = max;
    }

    /// Call before drawing scroll content. Sets the renderer clip to the
    /// content area so nothing overflows the scroll bounds. Returns the
    /// content rect (excludes the scrollbar column).
    ///
    /// Usage:
    ///   const cr = sa.pushClip(r, rect);
    ///   // draw content at (cr.x, cr.y - sa.scroll_offset)
    ///   sa.popClip(r);
    ///   sa.draw(r, rect); // draw the scrollbar on top
    pub fn pushClip(self: *const ScrollArea, r: *Renderer, rect: Rect) Rect {
        const cr = self.contentRect(rect);
        r.setClip(cr);
        return cr;
    }

    /// Remove the clip set by pushClip.
    pub fn popClip(_: *const ScrollArea, r: *Renderer) void {
        r.clearClip();
    }

    pub fn draw(self: *const ScrollArea, r: *Renderer, rect: Rect) void {
        const track = self.trackRect(rect);
        r.fillRoundRect(track, self.scrollbar_width / 2, self.track_color);

        if (self.thumbRect(rect)) |thumb| {
            const color = if (self.thumb_hovered) self.thumb_hover_color else self.thumb_color;
            r.fillRoundRect(thumb, (self.scrollbar_width -| 4) / 2, color);
        }
    }

    pub fn handleEvent(self: *ScrollArea, event: Event, rect: Rect) bool {
        switch (event) {
            .scroll => |ev| {
                if (self.content_height <= rect.height) return false;
                self.scroll_offset -= @as(i32, @intFromFloat(
                    ev.dy * @as(f32, @floatFromInt(self.line_height)),
                ));
                self.clampOffset(rect);
                return true;
            },
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };
                self.thumb_hovered = if (self.thumbRect(rect)) |thumb| thumb.contains(pt) else false;
                if (self.dragging) {
                    const new_offset = self.drag_start_offset + @as(i32, @intFromFloat(
                        @as(f32, @floatFromInt(m.y - self.drag_start_y)) *
                            @as(f32, @floatFromInt(self.content_height)) /
                            @as(f32, @floatFromInt(rect.height)),
                    ));
                    self.scroll_offset = new_offset;
                    self.clampOffset(rect);
                    return true;
                }
                return false;
            },
            .mouse_press => |m| {
                if (m.button == .left) {
                    const pt = Point{ .x = m.x, .y = m.y };
                    if (self.thumbRect(rect)) |thumb| {
                        if (thumb.contains(pt)) {
                            self.dragging = true;
                            self.drag_start_y = m.y;
                            self.drag_start_offset = self.scroll_offset;
                            return true;
                        }
                    }
                }
                return false;
            },
            .mouse_release => {
                if (self.dragging) {
                    self.dragging = false;
                    return true;
                }
                return false;
            },
            else => return false,
        }
    }

    pub fn preferredSize(_: *const ScrollArea) Size {
        return .{ .width = 12, .height = 0 };
    }
};
