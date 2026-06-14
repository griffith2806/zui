# Widgets Progress

## Status: Complete (M12/M13 + gap-close)

### Done
- Label, Button (ButtonStyle), TextField, Container, Checkbox, Slider — all previous
- ProgressBar (`src/widgets/progress_bar.zig`) — Tween-animated fill, track/fill colors, radius
- TabView (`src/widgets/tab_view.zig`) — tab bar, active underline, Signal(usize) changed, contentRect()
- ScrollArea (`src/widgets/scroll_area.zig`) — scrollbar track/thumb, drag, wheel, contentRect()
- TextArea (`src/widgets/text_area.zig`) — multiline editor, line split/merge, UTF-8 cursor, scroll_y
- ListView (`src/widgets/list_view.zig`) — scrollable item list, hover/selected highlight, Signal(usize) changed
- DropDown (`src/widgets/dropdown.zig`) — collapsed picker, popup list, Signal(usize) changed, key nav
- Tooltip (`src/widgets/tooltip.zig`) — hover-delay popup, auto-position, window-edge clamping
- Dialog (`src/widgets/dialog.zig`) — modal overlay, OK/Cancel signals, Escape closes
- Menu (`src/widgets/menu.zig`) — MenuItem list, separators, enabled/disabled, Signal(usize) selected, key nav

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Image widget (display Image type, optional scaling)
- RichText / formatted text
- Accessibility / screen reader integration
