# Figma Render Parity Progress

## Status: In Progress

Goal: zui renders *exactly* what Figma renders, full T0–T4 parity.

Backend: **D2D is the parity backend** (already has gradient/geometry/text/layer
plumbing). Software + OpenGL parity is a follow-up, not the primary target.

### Tiers
- **T0 Structure** — auto-layout → layouts, absolute position, constraints
- **T1 Surface** — gradients, per-corner radius + smoothing, per-side strokes
- **T2 Depth** — drop/inner shadow, layer/background blur
- **T3 Text** — line-height, letter-spacing, full DirectWrite
- **T4 Vector/transform** — SVG paths, rotation/scale, blend modes, masks

### Done
- [ M23a ] `src/style/paint.zig` — Paint/Gradient/GradientType/GradientStop/
  ImagePaint/ScaleMode/Corners/Border/StrokeAlign/Shadow/ShadowKind/Effect/
  BlendMode/Transform/Visual + MAX_GRADIENT_STOPS. Fixed-cap gradient stops (no
  alloc), 2x3 affine Transform with rotate/translate/scale helpers. 11 tests.
- [ M23a ] `Font` extended with `line_height` + `letter_spacing` (auto/0
  defaults, backward compatible). 2 tests.
- [ M23a ] `src/root.zig` — all paint types exported.
- [ M23k ] `src/accessibility/tree.zig` — `AccessTree` flattened pre-order layout:
  parent / first_child / last_child / next_sibling / prev_sibling arrays,
  root_first/root_last, childCount(), isRoot(). Zero-alloc, value-copyable.
  6 tests (empty, flat, nested, deep, multi-root, clamp).
- [ M23k ] `AccessNode.depth: u16 = 0` added (default 0 = flat tree, backward
  compatible). `uia.zig` — `UiaTree.layout` computed in `update()`;
  `WidgetProvider.fNavigate` handles Parent/FirstChild/LastChild/NextSibling/
  PreviousSibling via layout; `WindowProvider.wfNavigate` uses root_first/last;
  hit-testing prefers the deepest node. `main.zig` publishes a nested
  `Navigation` group. Validated live: 40/40 `tests/uia_test.py` pass; tree dump
  confirms `Navigation > {Dashboard, Controls, Search}`.
- [ M23h ] `src/layout/constraints.zig` — `Constraints`/`Constraint` (Figma
  start/end/start_end/center/scale on both axes) + `apply(parent_old, parent_new,
  child)`. 9 tests.
- [ M23f ] `src/graphics/path.zig` — SVG path model (`Vec2`, `Cubic`, `Quad`,
  `Arc`, `Cmd`) + `parse()` supporting M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z,
  implicit repeated commands, implicit separators, smooth-curve reflection.
  16 tests.
- [ M23b ] Renderer surface primitives:
  - `paint.Corners.maxRadius()` + `paint.sampleStops()` shared helpers.
  - Software renderer: real `fillCorners()` (per-corner arcs) and
    `fillLinearGradient()` (angle-projected, stop-sampled). 8 pixel tests incl.
    exact equivalence to `fillRoundRect` for uniform corners.
  - D2D / OpenGL / Vulkan: `fillCorners` + `fillLinearGradient` added
    (approximate — uniform max radius / midpoint colour — documented as
    follow-ups). Interface is uniform across all backends.
  - `zig build`, `-Dbackend=d2d`, `-Dbackend=vulkan` all compile.
  - NOTE: `-Dbackend=opengl` is broken *before* this change (Renderer lacks
    `drawImage` / `setClip` / `clearClip` / `clearTextQueue` used by main +
    widgets). Pre-existing gap, not introduced here.
- `zig build test` clean; live UIA suite 40/40 green.

- [ M23b2 ] D2D exact surface (`src/graphics/d2d/renderer.zig`, +259 lines):
  `fillCorners` builds an `ID2D1PathGeometry` (one arc per corner, radii clamped
  to min(w,h)/2) and fills via `FillGeometry`; `fillLinearGradient` builds an
  `ID2D1GradientStopCollection` + `ID2D1LinearGradientBrush`, projects the rect
  corners onto the direction for the axis, and clips to the rounded path when
  radii are non-zero. All COM objects released; stack-allocated stop buffer.
  Binds ID2D1PathGeometry/ID2D1GeometrySink/ID2D1GradientStopCollection/
  ID2D1LinearGradientBrush. `zig build -Dbackend=d2d` + `zig build test` green.
- [ M23b2 ] **Compile-latency bug found + fixed**: Zig only semantically
  analyses a function when it is referenced, so the D2D surface code was never
  actually compiled until a consumer called it. The first real call (from the
  `rove-design` example) exposed an illegal `[*]const anyopaque` in the
  `ID2D1GeometrySinkVtbl` placeholders (`AddBeziers`, `AddQuadraticBeziers`),
  changed to `*const anyopaque`. Lesson: verify new renderer primitives by
  calling them from an app, not just by building the library. D2D gradients +
  per-corner rounded rects now confirmed working at runtime.
- [ M23i ] 7 new widgets, each with UIA role + pattern:
  `Icon`, `ImageView`, `Avatar` (role `.image`), `Badge` (role `.label`),
  `Link` (role `.link`, UIA Hyperlink + Invoke), `ProgressRing` (role
  `.progress_bar`, RangeValue), `Toggle` (role `.checkbox`, Toggle pattern).
  `Role.image` + `Role.link` added; `uia.zig` maps them
  (`UIA_HyperlinkControlTypeId`, controlType, isKeyboardFocusable,
  roleSupportsInvoke). All exported from `root.zig`.
- [ M23i ] Gallery: new "Components" page (`Page.components`, `NAV_ITEMS`,
  `ComponentsState`, event/update/draw wiring, `buildAccessibilityTree` case,
  header title) demonstrating all 7 widgets. `tests/uia_test.py` gains
  `test_components` (Hyperlink / ProgressBar / CheckBox / Group / Text).
- Sidebar scrollbar: nav menu scrolls when content exceeds the viewport
  (`sidebar_scroll`, clipped viewport, track + thumb, scroll-aware UIA bounds).
  Win32 `WM_MOUSEWHEEL` was declared but never handled — now wired to
  `Event.scroll` (screen→client coords, delta/120), so wheel scrolling works
  for the sidebar and every `ScrollArea`/`ListView`.
- Validated live: 47/47 `tests/uia_test.py`; screenshots confirm the scrollbar
  and that wheel-down scrolls the nav + moves the thumb.

### In Progress
- (none)

### Blocked
- (none)

### Up Next
- M23c Effects: drop/inner shadow, layer blur, background blur (D2D effects)
- M23d Typography: Font line_height + letter_spacing → DirectWrite layout
- M23e Transforms: rotation/scale/flip in renderer + widget transform
- M23g Blend modes + arbitrary-shape masks
- M23j docs/figma.md importer contract
- Fix pre-existing OpenGL renderer gaps (drawImage/setClip/clearClip/clearTextQueue)
