# Style Progress

## Status: Complete (M3 + gap-close)

### Done
- Color type (`src/style/color.zig`) — rgb/rgba, lerp, premultiplied, fromU32/toU32
- Theme struct (`src/style/theme.zig`) — Theme.dark and Theme.light presets
- Font descriptor (`src/style/font.zig`) — Font{family, size_pt, weight, style}
  - Weight enum: thin/light/regular/medium/semibold/bold/extrabold/black
  - Style enum: normal/italic
  - Presets: Font.default(), Font.heading(), Font.caption(), Font.mono()

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Font descriptor wired into renderer (renderer still hardcodes Segoe UI Variable)
- CSS-like style inheritance / cascade
