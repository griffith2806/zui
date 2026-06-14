# Style Progress

## Status: Complete (M17 — Style + Stylesheet)

### Done
- Color type (`src/style/color.zig`) — rgb/rgba, lerp, premultiplied, fromU32/toU32
- Theme struct (`src/style/theme.zig`) — Theme.dark and Theme.light presets
- Font descriptor (`src/style/font.zig`) — Font{family, size_pt, weight, style}
  - Weight enum: thin/light/regular/medium/semibold/bold/extrabold/black
  - Style enum: normal/italic
  - Presets: Font.default(), Font.heading(), Font.caption(), Font.mono()
- Style struct (`src/style/style.zig`) — composable per-widget style overrides
  - All fields optional (fg, bg, border, radius, padding, font)
  - `merge(base, override)` — non-null override fields win
  - `Style.empty` constant
  - 3 unit tests: override wins, empty override, all-null empty
- Stylesheet parser (`src/style/stylesheet.zig`) — CSS-like flat key:value parser
  - Supports: bg, fg, border (#RRGGBB / #RRGGBBAA), radius (u32), padding (u32)
  - Comments (#), blank lines, unknown keys all handled gracefully
  - 6 unit tests covering basic parse, RGBA color, blanks/comments, unknown keys,
    invalid color errors, and colon-less lines
- root.zig exports: Style, Stylesheet (Font was already exported)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Font descriptor wired into renderer (renderer still hardcodes Segoe UI Variable)
- Selector support in Stylesheet (type/class/id selectors)
- CSS-like style inheritance / cascade
