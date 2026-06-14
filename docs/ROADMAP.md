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

## Milestone 2 — Basic Widgets
_Goal: render Label and Button, handle click._

- [ ] Widget base trait
- [ ] Label widget (text rendering)
- [ ] Button widget (click signal)
- [ ] Box layout (vertical + horizontal)
- [ ] Event dispatch from platform → widget tree

## Milestone 3 — Theming + More Widgets
_Goal: consistent look, usable widget set._

- [ ] Default light and dark themes
- [ ] TextField widget
- [ ] Container / Panel
- [ ] ScrollArea
- [ ] GridLayout

## Milestone 4 — OpenGL Backend
_Goal: GPU-accelerated rendering._

- [ ] OpenGL 3.3 core renderer backend
- [ ] Font atlas (glyph rasterization → texture)
- [ ] Batched draw calls

## Milestone 5 — Linux (X11) Backend
- [ ] x11 platform backend

## Milestone 6 — macOS (Cocoa) Backend
- [ ] cocoa platform backend (Objective-C interop via `@cImport`)

## Milestone 7 — Vulkan Backend
- [ ] Vulkan renderer backend

## Backlog
- Accessibility (a11y) tree
- Drag and drop
- IME / international input
- Animation system
- CSS-like style sheets
- Hot-reload for styles
