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

### Architecture
- Flat tree: window root → N widget children (all leaves)
- BSTR via SysAllocStringLen (oleaut32); SAFEARRAY runtime IDs via SafeArrayCreateVector
- COM ref-counting: WidgetProvider frees on Release; WindowProvider owned by UiaTree
- Bounding rects: logical client coords → physical pixels → screen coords via ClientToScreen
