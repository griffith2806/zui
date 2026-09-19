//! Shared text-metric helpers used by the renderer backends.
//!
//! Kept pure (no COM/GDI/HWND) so the width contract is unit-tested under the
//! default software test build, even though the callers are backend-specific.

const std = @import("std");

/// Logical width (px) from a DWrite text layout's metrics.
///
/// DWrite's `width` EXCLUDES the trailing whitespace of the last line, so a
/// lone space measures 0. Callers that advance a pen by the measured width
/// (word wrapping, inter-word gaps) would then collapse every space. Use the
/// width INCLUDING trailing whitespace, which is the real advance.
///
/// `width_including_trailing` is in DIPs; the renderers pass logical
/// coordinates straight through, so DIPs == logical pixels here.
pub fn widthFromDwriteMetrics(width_including_trailing: f32) u32 {
    if (!(width_including_trailing > 0.0)) return 0; // also rejects NaN
    return @intFromFloat(@ceil(width_including_trailing));
}

test "widthFromDwriteMetrics keeps a lone space (trailing whitespace included)" {
    // DWrite reports width=0 for " " but the advance is non-zero.
    try std.testing.expectEqual(@as(u32, 5), widthFromDwriteMetrics(4.2));
    try std.testing.expectEqual(@as(u32, 0), widthFromDwriteMetrics(0));
    // Negative / NaN must not panic on @intFromFloat.
    try std.testing.expectEqual(@as(u32, 0), widthFromDwriteMetrics(-1.0));
    try std.testing.expectEqual(@as(u32, 0), widthFromDwriteMetrics(std.math.nan(f32)));
}

test "widthFromDwriteMetrics rounds up a word width" {
    try std.testing.expectEqual(@as(u32, 31), widthFromDwriteMetrics(31.0));
    try std.testing.expectEqual(@as(u32, 32), widthFromDwriteMetrics(31.2));
}
