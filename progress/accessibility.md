# Accessibility Progress

## Status: Complete

### Done
- `src/accessibility/node.zig` — AccessNode, Role, State (platform-agnostic)
- `src/platform/win32/uia.zig` — Full COM UIA provider:
  - IRawElementProviderSimple (property queries: Name, ControlType, IsEnabled, etc.)
  - IRawElementProviderFragment (tree navigation: parent/child/sibling, bounding rect, runtime ID)
  - IRawElementProviderFragmentRoot (hit testing, focus)
  - WindowProvider + WidgetProvider (multi-interface COM via @fieldParentPtr)
  - UiaTree — thread-safe snapshot array, updated every frame
  - UIAutomationCore.dll loaded dynamically (graceful fallback)
- WM_GETOBJECT handler in window.zig → routes to UiaReturnRawElementProvider
- `Window.initUia / deinitUia / updateAccessibility` methods
- `Application.initUia / deinitUia / updateAccessibility` methods
- `accessNode()` on Button, Checkbox, Slider, Label, TextField, ProgressBar, TabView, ListView, DropDown
- `root.zig` exports AccessNode, Role, State
- `main.zig` wires up initUia + per-frame buildAccessibilityTree (nav items + Controls/Inputs pages)

### Validated
- UI Automation MCP tools (`get_ui_elements`, `get_page_state`) can enumerate named elements
- Navigation sidebar buttons visible as "button" role with correct labels
- Controls page: Search/Name text fields, Increment/Reset/Toggle buttons, slider, checkboxes, tab view
- Inputs page: list view, dropdown

### IME / CJK Composition + UIA Live Region (added)
- `Event.ime_composition` (ImeCompositionEvent with inline 192-byte buf) and `Event.ime_cancel`
- Win32 WM_IME_STARTCOMPOSITION / WM_IME_COMPOSITION / WM_IME_ENDCOMPOSITION handling
  - GCS_COMPSTR retrieved via ImmGetCompositionStringW (imm32.dll), converted UTF-16→UTF-8
  - Composition string stored inline in ImeCompositionEvent (no heap, ring-buffer safe)
- TextField: `ime_active`, `ime_composition`, `_value_scratch` fields
  - `accessNode()` now requires `alloc` param; exposes `committed + composition` in value field
  - `handleEvent` handles `.ime_composition` (copy to buffer) and `.ime_cancel` (clear state)
  - `draw()`: renders composition text after committed text in `theme.input_hint` colour + 1px underline
  - Cursor hidden while IME active (OS candidate window owns cursor display)
- `UiaTree.notifyImeCompositionChanged()` fires UIA_Text_TextChangedEventId (20015) on focused text widget
  - `UiaRaiseAutomationEvent` loaded dynamically from UIAutomationCore.dll
- `Application.notifyImeCompositionChanged()` — cross-platform wrapper (no-op on non-Windows)
- main.zig fires `app.notifyImeCompositionChanged()` on every `ime_composition` event

### Architecture
- Flat tree: window root → N widget children (all leaves)
- BSTR via SysAllocStringLen (oleaut32); SAFEARRAY runtime IDs via SafeArrayCreateVector
- COM ref-counting: WidgetProvider frees on Release; WindowProvider owned by UiaTree
- Bounding rects: logical client coords → physical pixels → screen coords via ClientToScreen
