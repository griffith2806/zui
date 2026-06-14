# zui Roadmap

## ✅ Milestone 0 — Foundations _(complete)_
_Goal: compiling skeleton with subsystem stubs and CI passing._

- [x] Directory structure and build.zig wired up
- [x] Geometry types (Rect, Size, Point) in `layout`
- [x] Color type in `style`
- [x] Event union in `events`
- [ ] Signal(T) generic in `signals`
- [x] Core event loop stub
- [x] Platform interface defined (win32 backend)
- [x] Renderer interface defined (software backend)

## ✅ Milestone 1 — Hello World Window _(complete)_
_Goal: open a window and paint a solid color._

- [x] win32 platform backend: create window, message loop
- [x] Software renderer: fill rect, present to window surface
- [x] Application struct wiring platform + renderer
- [x] `zig build run` shows a window — **verified live, dark-blue background, Escape closes**

## ✅ Milestone 2 — Basic Widgets _(complete)_
_Goal: render Label and Button, handle click._

- [x] Widget base trait
- [x] Label widget (text rendering with 8×8 bitmap font)
- [x] Button widget (click signal, hover/press states)
- [x] Box layout (vertical + horizontal, spacing, padding)
- [x] Signal(T) generic — typed, comptime-verified connect/emit
- [x] Event dispatch from platform → widget tree
- [x] WinUI-style dark dashboard demo — **verified live: header, nav, counter card, buttons, about overlay all working**

## ✅ Milestone 3 — Theming + More Widgets _(complete)_
_Goal: consistent look, usable widget set._

- [x] Theme struct — dark and light presets, runtime toggle
- [x] TextField widget — char_input events, cursor, backspace/delete/home/end/left/right
- [x] Container / Panel — title bar, contentRect(), themed borders
- [x] GridLayout — configurable cols/rows/gap/padding, compute + measure
- [x] WM_CHAR → char_input event in Win32 backend
- [x] Validated live: dark↔light toggle, typed text + live greeting, 2×2 grid cells

## ✅ Milestone 4 — OpenGL Backend _(complete)_
_Goal: GPU-accelerated rendering._

- [x] WGL context creation with GL 3.3 core profile bootstrap (`src/platform/win32/gl_context.zig`)
- [x] GL 3.3 function pointer table loaded via wglGetProcAddress (`src/graphics/opengl/gl.zig`)
- [x] Font atlas texture 768×8 R8 from 8×8 bitmap font (`src/graphics/opengl/font_atlas.zig`)
- [x] Batched quad renderer — solid rects + text quads, single VAO/VBO flush
- [x] `-Dbackend=software|opengl` build option; comptime shim in `src/graphics/renderer.zig`
- [x] Validated live: `zig build -Dbackend=opengl` renders identical dashboard via GPU

## Milestone 5 — Linux (X11) Backend
- [ ] x11 platform backend

## Milestone 6 — macOS (Cocoa) Backend
- [ ] cocoa platform backend (Objective-C interop via `@cImport`)

## Milestone 7 — Vulkan Backend
- [ ] Vulkan renderer backend

## ✅ Milestone 8 — Showcase Demo _(complete)_
_Goal: a single polished app that exercises every completed subsystem — the zui equivalent of a component gallery._

- [x] WPF UI–style sidebar navigation (5 pages, active indicator, accent icon)
- [x] Dashboard page — 3 stat cards (GridLayout 3×1), counter card (Signal demo), feature list, BoxLayout strip
- [x] Controls page — TextField (search + name), Button variants, Toggle widgets, progress bars, accent swatch row
- [x] Colors page — accent ramp, system colors, neutral ramp, Color.lerp gradient demo
- [x] Layout page — BoxLayout vertical + horizontal, GridLayout 2×3, 3×1 stat grid, Container titled panel
- [x] About page — 5× scaled logo, expandable architecture notes section
- [x] Dark/light theme toggle wired throughout all pages
- [x] drawTextScaled() on both software + OpenGL backends for large headings
- [x] Validated live: all 5 pages navigate correctly, all widgets interactive

## ✅ Milestone 9 — Fluent Visual Polish _(complete)_
_Goal: Mica/Acrylic DWM backdrop, rounded corners, alpha blending — closing the gap with WPF UI._

- [x] Dark title bar + Mica backdrop via `DwmSetWindowAttribute` (Win32) — title bar has frosted glass blur
- [x] Rounded window corners via `DWMWA_WINDOW_CORNER_PREFERENCE` — Win32 system-level rounding
- [x] `fillRoundRect(rect, radius, color)` in software renderer — pixel-accurate corner arc with alpha blend
- [x] Alpha blending in software renderer — `blendPixel` composites semi-transparent draws
- [x] `fillRoundRect` in OpenGL renderer — SDF fragment shader with `smoothstep` anti-aliasing
- [x] `uniform1f` / `uniform4f` in `gl.Gl` for SDF uniforms
- [x] Showcase updated: cards, nav items, search bar all use rounded corners
- [x] Validated live: both software and OpenGL backends render rounded cards correctly

## Backlog
- Accessibility (a11y) tree
- Drag and drop
- IME / international input
- Animation system (hover fade ~150ms ease-out, page transitions)
- Mica client-area compositing (requires DirectComposition or UpdateLayeredWindow)
- CSS-like style sheets
- Hot-reload for styles
