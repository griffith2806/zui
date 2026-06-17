const std        = @import("std");
const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Point      = @import("../layout/geometry.zig").Point;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const Event      = @import("../events/event.zig").Event;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

const ACCENT  = Color.rgb(0, 103, 192);
const FG      = Color.rgb(255, 255, 255);
const FG_SEC  = Color.rgb(178, 178, 185);
const BG_CARD = Color.rgb(36, 36, 38);
const SEP     = Color.rgb(55, 55, 60);

pub const TreeNode = struct {
    label:        []const u8,
    depth:        u32  = 0,
    expanded:     bool = true,
    has_children: bool = false,
};

pub const TreeView = struct {
    nodes:       []TreeNode,
    selected:    ?usize = null,
    hovered:     ?usize = null,
    item_height: u32    = 28,
    indent_w:    u32    = 20,

    /// Returns the list of visible node indices respecting expanded state.
    /// Returns the count of items written.
    pub fn visibleItems(self: *const TreeView, out: []usize) usize {
        var count: usize = 0;
        // Track whether each depth level is "open" (all ancestors expanded).
        // We use a small stack indexed by depth.
        var depth_open: [16]bool = .{true} ** 16;

        for (self.nodes, 0..) |node, i| {
            // Check if all ancestors are expanded
            const depth = node.depth;

            // Is this node's parent open?
            const parent_open = if (depth == 0) true else depth_open[depth - 1];
            if (!parent_open) {
                // Hidden — also mark this depth as closed
                depth_open[depth] = false;
                continue;
            }

            // Node is visible
            if (count < out.len) {
                out[count] = i;
                count += 1;
            }

            // Record whether children at depth+1 are visible
            if (depth + 1 < depth_open.len) {
                depth_open[depth + 1] = node.expanded;
            }
        }
        return count;
    }

    pub fn handleEvent(self: *TreeView, ev: Event, rect: Rect) void {
        var vis_buf: [256]usize = undefined;
        const vis_count = self.visibleItems(&vis_buf);
        const vis = vis_buf[0..vis_count];

        switch (ev) {
            .mouse_move => |m| {
                const pt = Point{ .x = m.x, .y = m.y };
                self.hovered = null;
                if (!rect.contains(pt)) return;
                const rel_y = m.y - rect.y;
                if (rel_y < 0) return;
                const idx = @as(usize, @intCast(rel_y)) / @as(usize, self.item_height);
                if (idx < vis.len) self.hovered = vis[idx];
            },
            .mouse_press => |m| {
                if (m.button != .left) return;
                const pt = Point{ .x = m.x, .y = m.y };
                if (!rect.contains(pt)) return;
                const rel_y = m.y - rect.y;
                if (rel_y < 0) return;
                const idx = @as(usize, @intCast(rel_y)) / @as(usize, self.item_height);
                if (idx < vis.len) {
                    const node_idx = vis[idx];
                    self.selected = node_idx;
                    if (self.nodes[node_idx].has_children) {
                        self.nodes[node_idx].expanded = !self.nodes[node_idx].expanded;
                    }
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *const TreeView, r: *Renderer, rect: Rect) void {
        r.setClip(rect);
        defer r.clearClip();

        var vis_buf: [256]usize = undefined;
        const vis_count = self.visibleItems(&vis_buf);
        const vis = vis_buf[0..vis_count];

        for (vis, 0..) |node_idx, row| {
            const node = &self.nodes[node_idx];
            const item_y = rect.y + @as(i32, @intCast(row)) * @as(i32, @intCast(self.item_height));
            const item_rect = Rect.init(rect.x, item_y, rect.width, self.item_height);

            // Background highlight
            if (self.selected != null and self.selected.? == node_idx) {
                r.fillRect(item_rect, ACCENT);
            } else if (self.hovered != null and self.hovered.? == node_idx) {
                r.fillRect(item_rect, Color.rgba(255, 255, 255, 20));
            }

            const indent_x = rect.x + @as(i32, @intCast(node.depth * self.indent_w));
            const text_y   = item_y + @as(i32, @intCast(self.item_height / 2)) - 7;

            // Expand/collapse triangle for nodes with children
            if (node.has_children) {
                // Draw a simple arrow using two small filled rects
                const tri_x = indent_x;
                const tri_cy = item_y + @as(i32, @intCast(self.item_height / 2));
                const tri_color = if (self.selected != null and self.selected.? == node_idx) FG else FG_SEC;
                if (node.expanded) {
                    // Down arrow: wide top bar tapering
                    r.fillRect(Rect.init(tri_x,     tri_cy - 3, 9, 2), tri_color);
                    r.fillRect(Rect.init(tri_x + 2, tri_cy - 1, 5, 2), tri_color);
                    r.fillRect(Rect.init(tri_x + 4, tri_cy + 1, 1, 2), tri_color);
                } else {
                    // Right arrow
                    r.fillRect(Rect.init(tri_x, tri_cy - 4, 2, 8), tri_color);
                    r.fillRect(Rect.init(tri_x + 2, tri_cy - 2, 2, 4), tri_color);
                    r.fillRect(Rect.init(tri_x + 4, tri_cy, 2, 2), tri_color);
                }
            }

            // Label — offset past the triangle area (12px) and additional indent
            const label_x = indent_x + 14;
            const label_color = if (self.selected != null and self.selected.? == node_idx) FG else FG_SEC;
            r.drawText(node.label, label_x, text_y, label_color);

            // Subtle row separator
            if (row + 1 < vis.len) {
                r.fillRect(Rect.init(rect.x, item_y + @as(i32, @intCast(self.item_height)) - 1, rect.width, 1),
                    Color.rgba(255, 255, 255, 8));
            }
        }
    }

    pub fn accessNode(self: *const TreeView, rect: Rect) AccessNode {
        const name: []const u8 = if (self.selected) |sel|
            self.nodes[sel].label
        else
            "Tree";
        return .{
            .role   = .list,
            .name   = name,
            .bounds = rect,
            .state  = .{ .enabled = true },
        };
    }

    pub fn preferredSize(self: *const TreeView) Size {
        var vis_buf: [256]usize = undefined;
        const vis_count = self.visibleItems(&vis_buf);
        return .{
            .width  = 200,
            .height = @intCast(vis_count * self.item_height),
        };
    }
};
