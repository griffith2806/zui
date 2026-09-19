//! Pure rounded-rect geometry shared by the renderer backends.
//!
//! Kept dependency-free so the corner-radius contract is unit-tested under the
//! default software test build.

const std = @import("std");

/// The circular corner radius a backend should use for a `width` x `height`
/// rect. Clamps to half the smaller side, so an over-large "pill" radius (999)
/// yields a stadium (rounded ends, flat top/bottom), not an ellipse.
///
/// Direct2D's FillRoundedRectangle clamps `radiusX` and `radiusY` INDEPENDENTLY
/// per axis, so radiusX=999, radiusY=999 on a 150x44 rect become 75 x 22 and the
/// two corner arcs meet at the centre: a full ellipse. Clamping here first keeps
/// D2D matching the software rasterizer (which already clamps) and CSS
/// `border-radius`, where 999px on a wide short box is a pill.
pub fn clampCornerRadius(radius: u32, width: u32, height: u32) u32 {
    return @min(radius, @min(width, height) / 2);
}

test "clampCornerRadius makes a pill, not an ellipse" {
    try std.testing.expectEqual(@as(u32, 22), clampCornerRadius(999, 150, 44));
    try std.testing.expectEqual(@as(u32, 8), clampCornerRadius(8, 150, 44));
    // A circle: the clamp is half the (equal) sides.
    try std.testing.expectEqual(@as(u32, 5), clampCornerRadius(999, 10, 10));
    // A radius already inside the box is untouched.
    try std.testing.expectEqual(@as(u32, 4), clampCornerRadius(4, 100, 40));
    try std.testing.expectEqual(@as(u32, 0), clampCornerRadius(999, 0, 44));
}
