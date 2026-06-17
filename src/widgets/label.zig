const Color      = @import("../style/color.zig").Color;
const Rect       = @import("../layout/geometry.zig").Rect;
const Size       = @import("../layout/geometry.zig").Size;
const Renderer   = @import("../graphics/renderer.zig").Renderer;
const AccessNode = @import("../accessibility/node.zig").AccessNode;

pub const Label = struct {
    text:       []const u8,
    color:      Color = Color.white,
    /// When non-zero, text is wrapped at this pixel width.
    wrap_width: u32   = 0,

    pub fn draw(self: *const Label, r: *Renderer, rect: Rect) void {
        if (self.wrap_width > 0)
            drawWrapped(r, self.text, rect.x, rect.y, self.color, self.wrap_width)
        else
            r.drawText(self.text, rect.x, rect.y, self.color);
    }

    pub fn accessNode(self: *const Label, rect: Rect) AccessNode {
        return .{ .role = .label, .name = self.text, .bounds = rect };
    }

    pub fn preferredSize(self: *const Label, r: *const Renderer) Size {
        if (self.wrap_width > 0) return .{ .width = self.wrap_width, .height = 18 };
        return .{ .width = r.textWidth(self.text), .height = 18 };
    }
};

/// Greedy word-wrap: draw `text` at (x, y) breaking lines at `max_w` pixels.
/// Explicit `\n` characters also force a line break.
fn drawWrapped(r: *Renderer, text: []const u8, x: i32, y: i32, color: Color, max_w: u32) void {
    const LINE_H: i32 = 18;
    var line_y = y;
    var i: usize = 0;

    outer: while (i < text.len) {
        var j = i;
        var last_space: usize = i; // last position where we can break

        while (j < text.len) {
            if (text[j] == '\n') {
                r.drawText(text[i..j], x, line_y, color);
                line_y += LINE_H;
                i = j + 1;
                continue :outer;
            }
            // Check if text[i..j+1] fits within max_w
            if (r.textWidth(text[i .. j + 1]) > max_w) {
                if (last_space > i) {
                    // Break before the word that pushed us over
                    r.drawText(text[i..last_space], x, line_y, color);
                    line_y += LINE_H;
                    i = last_space + 1; // skip the space
                } else {
                    // No space found — hard-break right here
                    const end = if (j == i) j + 1 else j;
                    r.drawText(text[i..end], x, line_y, color);
                    line_y += LINE_H;
                    i = end;
                }
                continue :outer;
            }
            if (text[j] == ' ') last_space = j;
            j += 1;
        }
        // Remaining text all fits on one line
        r.drawText(text[i..j], x, line_y, color);
        break;
    }
}
