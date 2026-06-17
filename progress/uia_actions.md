# UIA Action Patterns Progress

## Status: Complete

### Done

- Added `invoke_fn`, `toggle_fn`, and `ctx` optional fields to `AccessNode` in `src/accessibility/node.zig`
  — all new fields default to null, fully backward compatible with existing code

- Added four COM action pattern vtables to `WidgetProvider` in `src/platform/win32/uia.zig`:
  - **IInvokeProvider** (`IID {54FCB508-A951-4836-A9D5-B99E04C99A82}`) — button roles
    - `Invoke()` calls `node.invoke_fn(node.ctx)` if non-null
  - **IToggleProvider** (`IID {56D00BD0-C4F4-4C6C-A6CA-6E68F72C27E3}`) — checkbox roles
    - `Toggle()` calls `node.toggle_fn(node.ctx)`
    - `get_ToggleState` reads `node.state.checked`
  - **IValueProvider** (`IID {C7935180-6FB3-4201-B174-7DF73ADBF64A}`) — text_field, text_area, slider
    - `get_Value` returns `node.value` as BSTR
    - `SetValue` is a no-op stub (no write-back yet)
    - `get_IsReadOnly` reads `node.state.read_only`
  - **IRangeValueProvider** (`IID {36DC7AEF-33E6-4691-AFE1-2BE7274B3D33}`) — slider, progress_bar
    - `get_Value` parses `node.value` as f64
    - Min=0.0, Max=1.0, SmallChange=0.01, LargeChange=0.1 (fixed for now)
    - `SetValue` is a no-op stub

- Updated `GetPatternProvider` in `WidgetProvider` to return the correct face pointer based on role

- Updated `QueryInterface` in all six faces (`simple`, `fragment`, `invoke_face`, `toggle_face`, `value_face`, `rngval_face`) to route to the unified `sQI` logic

- Added `IsInvokePatternAvailable`, `IsTogglePatternAvailable`, `IsValuePatternAvailable` property responses to `GetPropertyValue`

- Updated `buildAccessibilityTree` in `src/main.zig`:
  - Changed `controls`, `animations`, `overlays` parameters from `*const T` → `*T` to allow passing mutable widget pointers as `ctx`
  - Wired `invoke_fn` callbacks for all buttons in Controls, Overlays, and Animations pages
  - Wired `toggle_fn` callbacks for `cb_notify` and `cb_compact` checkboxes

- `zig build` passes clean; `zig build test` passes clean

### Blocked
— nothing

### Up Next
- IValueProvider.SetValue() write-back: would require a callback similar to invoke_fn
- IRangeValueProvider: expose real min/max/step from slider widget rather than fixed constants
- UiaRaiseAutomationEvent when state changes (so AT gets notified without polling)
