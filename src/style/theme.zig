const Color = @import("color.zig").Color;

pub const Theme = struct {
    bg:                   Color,
    bg_panel:             Color,
    bg_header:            Color,
    accent:               Color,
    fg:                   Color,
    fg_muted:             Color,
    divider:              Color,
    btn_bg:               Color,
    btn_hover:            Color,
    btn_press:            Color,
    input_bg:             Color,
    input_border:         Color,
    input_border_focused: Color,
    input_hint:           Color,

    pub const dark = Theme{
        .bg                   = Color.rgb(32,  32,  32),
        .bg_panel             = Color.rgb(44,  44,  44),
        .bg_header            = Color.rgb(24,  24,  24),
        .accent               = Color.rgb(0,  120, 212),
        .fg                   = Color.white,
        .fg_muted             = Color.rgb(160, 160, 160),
        .divider              = Color.rgb(60,  60,  60),
        .btn_bg               = Color.rgb(45,  45,  48),
        .btn_hover            = Color.rgb(62,  62,  66),
        .btn_press            = Color.rgb(28,  28,  28),
        .input_bg             = Color.rgb(30,  30,  30),
        .input_border         = Color.rgb(70,  70,  70),
        .input_border_focused = Color.rgb(0,  120, 212),
        .input_hint           = Color.rgb(90,  90,  96),
    };

    pub const light = Theme{
        .bg                   = Color.rgb(243, 243, 243),
        .bg_panel             = Color.rgb(255, 255, 255),
        .bg_header            = Color.rgb(228, 228, 228),
        .accent               = Color.rgb(0,  120, 212),
        .fg                   = Color.rgb(0,   0,   0),
        .fg_muted             = Color.rgb(100, 100, 100),
        .divider              = Color.rgb(200, 200, 200),
        .btn_bg               = Color.rgb(225, 225, 225),
        .btn_hover            = Color.rgb(210, 210, 210),
        .btn_press            = Color.rgb(195, 195, 195),
        .input_bg             = Color.rgb(255, 255, 255),
        .input_border         = Color.rgb(180, 180, 180),
        .input_border_focused = Color.rgb(0,  120, 212),
        .input_hint           = Color.rgb(170, 170, 178),
    };
};
