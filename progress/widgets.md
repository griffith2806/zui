# Widgets Progress

## Status: Complete (M12/M13)

### Done
- Label widget (`src/widgets/label.zig`) — text display, preferredSize
- Button widget (`src/widgets/button.zig`) — hover/press states, Signal(void) clicked, Tween hover animation
- ButtonStyle struct — themeable bg/bg_hover/bg_press/fg
- TextField widget (`src/widgets/text_field.zig`) — typed text, cursor, char_input, backspace/delete/home/end/left/right, focus/blur, placeholder hint, Ctrl+A/C/V clipboard
- Container widget (`src/widgets/container.zig`) — panel with optional title bar, contentRect(), themed borders
- Checkbox widget (`src/widgets/checkbox.zig`) — checked/unchecked, Tween check animation, Signal(bool) changed
- Slider widget (`src/widgets/slider.zig`) — 0..1 float value, drag interaction, Signal(f32) changed, styled track+thumb

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- ScrollArea
- Tab/Panel switcher
- Progress bar widget (currently drawn inline in demo)
