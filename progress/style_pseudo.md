# Style Pseudo-States Progress

## Status: Complete

### Done
- `PseudoState` packed struct (`u8` bitfield) with flags: `hover`, `focus`, `disabled`, `active`, `checked`
  - `bits() u8` — returns the raw backing value
  - `isDefault() bool` — true when no flags are set
- `PseudoStateTag` enum (`hover/focus/disabled/active/checked`) used for array indexing
- `WidgetStylesheet` struct (zero-allocation, stack-only):
  - `base: Style` — baseline style applied unconditionally
  - `overrides: [5]?Style` — per-pseudo-state override slots
  - `setOverride(which: PseudoStateTag, style: Style)` — store override for one state
  - `getOverride(which: PseudoStateTag) ?Style` — retrieve override
  - `resolve(pseudo: PseudoState) Style` — merge chain: base → hover → focus → active → disabled → checked
  - `disabled` overrides `hover` by design (applied after)
- `src/style/pseudo.zig` — 8 unit tests covering all major resolution paths
- `Button` widget updated:
  - Added `stylesheet: ?WidgetStylesheet = null` field (backward compat: null = use legacy `style`)
  - Added `focused: bool = false` field
  - `pseudoState() PseudoState` — builds current PseudoState from `hovered/focused/pressed`
  - `handleEvent` now tracks `focus_gained` / `focus_lost` to toggle `focused`
  - `draw()` dispatches to stylesheet path when `stylesheet != null`, legacy path otherwise
- `src/root.zig` — exports `PseudoState`, `PseudoStateTag`, `WidgetStylesheet`
- `docs/API.md` — new "PseudoState / WidgetStylesheet" section in Style chapter
- `zig build` and `zig build test` — clean (zero errors, all tests pass)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next
- Extend other widgets (TextField, Checkbox, Slider) with `WidgetStylesheet` support
- Stylesheet CSS-like text parser with pseudo-state section syntax (e.g. `[hover]`)
- Propagate `focused` state from `FocusManager` rather than raw focus events
