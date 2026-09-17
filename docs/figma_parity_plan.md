# Figma Render Parity Plan (T0–T4), D2D-first, nested UIA

Goal: zui renders exactly what Figma renders, full T0–T4 parity, with every
piece UIA-compatible.

## Guiding rules

1. **Subsystem boundaries hold** (`docs/architecture.md`): `style` imports only
   `core`; `graphics` imports `core/style/layout`; `widgets` imports everything
   below; `accessibility` + `platform` stay independent. Do not leak
   `graphics.Image` into `style`.
2. **No hidden allocations** — every allocating function takes `Allocator`; new
   data types must be value-copyable (fixed-cap arrays or caller-owned slices).
3. **Comptime where possible** — paint/gradient types resolved statically where
   the type is known.
4. **UIA compatibility is mandatory, not retrofitted** — every new widget, role,
   and pattern lands in the accessibility layer in the same milestone.

## Backend policy

- **D2D = parity backend** (full T0–T4).
- **Software + OpenGL** = compile-safe stubs for new primitives now; parity
  deferred. Interface changes always land in the shim and all three backends so
  `zig build` never breaks.

## Subsystem placement

| Deliverable | Subsystem | File |
|---|---|---|
| Paint/Gradient/Corners/Border/Shadow/Effect/Blend/Transform/Visual | style | `src/style/paint.zig` |
| `line_height`, `letter_spacing` on Font | style | `src/style/font.zig` |
| Renderer draw API (gradient, per-corner, stroke, path, shadow, transform) | graphics | `src/graphics/renderer.zig` (shim) + `d2d/` primary, `software/` `opengl/` follow |
| SVG path model + parser | graphics | `src/graphics/path.zig` |
| Constraint/absolute layout (Figma pin/scale) | layout | `src/layout/constraints.zig` |
| New widgets (icon, image, avatar, badge, link, progress-ring, toggle) | widgets | `src/widgets/*.zig` |
| New roles + patterns | accessibility | `src/accessibility/node.zig` + `src/platform/win32/uia.zig` |
| Figma→widget idiom guide + helper (agent contract) | docs | `docs/figma.md` |

## New widgets + their UIA role

| Widget | Role | Pattern | Control type |
|---|---|---|---|
| `Icon` / `Image` widget | `image` | — (non-focusable) | group/text + name |
| `Avatar` | `image` | — | group/text + name |
| `Badge` | `text`/`group` | — | text |
| `Link` | `link` | Invoke | `UIA_HyperlinkControlTypeId` (50005) |
| `ProgressRing` | `progress_bar` | RangeValue | `UIA_ProgressBarControlTypeId` |
| `Toggle` switch | `checkbox` | Toggle | `UIA_CheckBoxControlTypeId` |

## UIA hierarchy (nested tree)

Replaces the current flat tree (window root → N widget leaves).

- `AccessNode` gains a `children` slice (arena-owned, like `name`).
- `UiaTree` snapshot stores a tree, not a flat array; rebuilt each frame.
- `uia.zig`: `IRawElementProviderFragment.Navigate` (parent / first-child /
  next-sibling) walks the real hierarchy; hit-testing recurses.
- Containers, groups, dialogs, menus become true parents; leaf widgets their
  children.
- `main.zig buildAccessibilityTree` emits nested nodes.
- Validation via `get_page_state` / `get_ui_elements` confirms the nested tree.

## Milestones (dependency-ordered)

### Foundation

- **M23a — Paint/Visual model** (`src/style/paint.zig`): `Paint`
  (solid/gradient/image), `GradientType{linear,radial,angular,diamond}`,
  `GradientStop`, `Gradient`, `ScaleMode`, `Corners` (tl/tr/br/bl + smoothing),
  `Border` (per-side widths, align inside/center/outside, dash),
  `Shadow{kind:drop|inner, color, offset, blur, spread}`, `Effect`
  (shadow / layer_blur / background_blur), `BlendMode`, `Transform` (2x3 affine),
  `Visual` (fills/strokes/effects/corners/blend/opacity/transform). Extend `Font`
  with `line_height`, `letter_spacing`. Export from `root.zig`. Pure data, no
  UIA impact. Tests alongside.

### Renderer (D2D-first)

- **M23b — Surface (T1)**: gradient fills, per-corner radius + smoothing,
  per-side strokes. Renderer interface + D2D.
- **M23c — Effects (T2)**: drop/inner shadow, layer/background blur.
- **M23d — Typography (T3)**: `line_height`/`letter_spacing` →
  `IDWriteTextLayout`.
- **M23e — Transforms (T4)**: rotation/scale/flip; UIA bounds stay logical.
- **M23f — Vector (T4)**: `src/graphics/path.zig`, SVG parse, geometry
  fill/stroke, boolean ops.
- **M23g — Blend modes + masks (T4)**.

### Layout

- **M23h — Constraints (T0)**: `src/layout/constraints.zig` pin/scale +
  absolute positioning.

### Accessibility (parallel-safe)

- **M23k — UIA hierarchy**: nested `AccessNode` + `UiaTree` + fragment
  navigation + hit-testing. Blocks M23i's composite-widget UIA wiring.

### Widgets + UIA + importer

- **M23i — New widgets** (`Icon`, `Image`, `Avatar`, `Badge`, `Link`,
  `ProgressRing`, `Toggle`) — each with `accessNode()` + role + pattern in the
  same change.
- **M23j — `docs/figma.md`**: Figma-node → zui-widget + Role/name/action
  contract so the LLM agent's generated code is UIA-complete by construction.

## Cross-cutting UIA checklist (applies to all new widgets)

Each new widget must, in the same milestone:

- Implement `accessNode()` returning an `AccessNode` with correct `Role`,
  `name`, `value`, `bounds`, and `state`.
- Add its `Role` to the enum in `src/accessibility/node.zig`.
- Map it in `uia.zig`: `controlType()`, `isKeyboardFocusable()`, pattern fns
  (`roleSupportsInvoke/Toggle/Value/RangeValue`), and `providerFor()`.
- Wire `invoke_fn` / `toggle_fn` (with `ctx`) so UIA `Invoke`/`Toggle` actually
  fire the signal.
- Appear in the Component Gallery: `Page` variant + `NAV_ITEMS` + page state +
  `handleEvent`/`update`/`draw` + `buildAccessibilityTree` accessNodes +
  `test_<page>` in `tests/uia_test.py`.

## Validation

- `zig build test` after every milestone.
- `zig build run` + `launch.ps1` + ui-automation MCP: `get_page_state` /
  `get_ui_elements` to confirm the UIA tree (roles, names, bounds) and visual
  parity.
- WPF UI Gallery as visual reference; Figma MCP to read the target design and
  diff against rendered output.

## Execution order

1. M23a (paint model) — no deps, establishes the contract everything renders from.
2. M23k (UIA hierarchy) — independent, parallel-safe.
3. M23b → M23c → M23d → M23e/f/g (renderer), M23h (layout) — parallel.
4. M23i (widgets) after M23a + M23k; M23j (doc) after M23i.
