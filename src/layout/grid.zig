const std  = @import("std");
const Rect = @import("geometry.zig").Rect;
const Size = @import("geometry.zig").Size;

pub const GridLayout = struct {
    cols:   u32 = 2,
    rows:   u32 = 2,
    gap:    u32 = 8,
    padding: u32 = 0,

    pub fn compute(self: GridLayout, bounds: Rect, out: []Rect) void {
        if (self.cols == 0 or self.rows == 0) return;
        const p: i32 = @intCast(self.padding);
        const g: u32 = self.gap;

        const avail_w = bounds.width -| self.padding * 2 -| g * (self.cols -| 1);
        const avail_h = bounds.height -| self.padding * 2 -| g * (self.rows -| 1);
        const cell_w  = avail_w / self.cols;
        const cell_h  = avail_h / self.rows;

        for (out, 0..) |*r, i| {
            const col: u32 = @intCast(i % self.cols);
            const row: u32 = @intCast(i / self.cols);
            r.* = Rect.init(
                bounds.x + p + @as(i32, @intCast(col * (cell_w + g))),
                bounds.y + p + @as(i32, @intCast(row * (cell_h + g))),
                cell_w,
                cell_h,
            );
        }
    }

    pub fn measure(self: GridLayout, cell: Size) Size {
        const p = self.padding * 2;
        const g_x = self.gap * (self.cols -| 1);
        const g_y = self.gap * (self.rows -| 1);
        return .{
            .width  = cell.width  * self.cols + g_x + p,
            .height = cell.height * self.rows + g_y + p,
        };
    }
};

test "grid 2x2 cells" {
    const layout = GridLayout{ .cols = 2, .rows = 2, .gap = 4, .padding = 0 };
    const bounds = Rect.init(0, 0, 100, 100);
    var rects: [4]Rect = undefined;
    layout.compute(bounds, &rects);
    try @import("std").testing.expectEqual(@as(i32, 0),  rects[0].x);
    try @import("std").testing.expectEqual(@as(i32, 52), rects[1].x);
    try @import("std").testing.expectEqual(@as(i32, 52), rects[3].x);
}
