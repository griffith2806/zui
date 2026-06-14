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

## ✅ Milestone 10 — GDI Typography + Animations _(complete)_

_Goal: crisp ClearType text, animated transitions._

- [x] GDI text pipeline: queue drawText commands → BitBlt DIB → flush on screen DC with ClearType
- [x] Segoe UI Variable loaded at 7 physical sizes (14–80px body to display)
- [x] Per-monitor V2 DPI awareness: physical pixel buffer, logical event coordinates
- [x] `fillRect` alpha-blend path for semi-transparent fills (modal scrims, hover tints)
- [x] Hover fade animations on buttons and nav items
- [x] `Application.deltaSeconds()` + `capFps(60)` frame timing

## ✅ Milestone 11 — Interactive Widget Expansion _(complete)_

_Goal: Checkbox, Slider, ProgressBar, TabView, DropDown — full Controls/Inputs gallery page._

- [x] Checkbox — check/uncheck, label, signal
- [x] Slider — drag thumb, value 0–1, signal
- [x] ProgressBar — determinate fill with label
- [x] TabView — tab strip with content switching
- [x] DropDown — open/close list, item selection, keyboard navigation
- [x] Clipboard read/write (Win32 `GetClipboardData` / `SetClipboardData`)
- [x] TextField horizontal scroll (`view_start` byte-offset, mutable draw)
- [x] Modifier key tracking (Ctrl/Shift/Alt) for key events

## ✅ Milestone 12 — Overlay Widgets _(complete)_

_Goal: Dialog, Menu, Tooltip on the Overlays gallery page._

- [x] Dialog — modal with title, OK/Cancel, Signal connections, Escape to dismiss
- [x] Dialog overlay: Fluent-style semi-transparent scrim (background shapes dimmed and visible; GDI text cleared before draw so page text doesn't bleed above scrim)
- [x] Dialog positioning: centered using logical win_rect (fixed physical-pixel coordinate bug)
- [x] Menu — popup context menu at button anchor, item selection, separators, disabled items
- [x] Tooltip — 0.5s hover delay, positioned near hover target

---

## Milestone 13 — Text Clipping + Layout Completion

_Goal: text never overflows its container; FlowLayout wrapping and BoxLayout flex._

- [ ] Text clipping: scissor rect before `flushText` so GDI text clips to its container bounds
- [ ] `FlowLayout` — wraps children like CSS `flex-wrap: wrap`, gap, alignment
- [ ] `BoxLayout` flex factors — grow/shrink proportion, min-size constraints
- [ ] `Renderer.setClip(rect)` / `clearClip()` API exposed to widgets
- [ ] Validated live: long text in TextField/Label clips at container edge

## Milestone 14 — ScrollArea + TextArea

_Goal: scrollable content containers and multiline text editing._

- [ ] `ScrollArea` — vertical/horizontal scrollbars, mouse-wheel scroll, drag-thumb
- [ ] `TextArea` — multiline edit: Enter inserts newline, word-wrap, caret per line
- [ ] `TextArea` clipboard (Ctrl+A select all, Ctrl+C/V/X), undo stack
- [ ] Scrollbar drawn by renderer (narrow rounded track + thumb, themed)
- [ ] ScrollArea wraps any child widget; content clips to viewport
- [ ] Validated live: long text list scrollable, TextArea multiline input working

## Milestone 15 — ListView + FocusManager

_Goal: data list widget with selection; keyboard Tab traversal across all widgets._

- [ ] `ListView` — renders a `[][]const u8` or generic `[]T`, selection highlight, scroll integration
- [ ] `ListView` keyboard: Up/Down arrows move selection, Enter confirms
- [ ] `FocusManager` — ordered focus ring, Tab/Shift-Tab cycles, each widget reports `isFocusable()`
- [ ] Focus ring drawn as accent-color outline (2px, rounded)
- [ ] Win32 `WM_SETFOCUS` / `WM_KILLFOCUS` mapped to focus events
- [ ] Validated live: Tab moves focus through TextField → Button → Checkbox → Slider

## Milestone 16 — Image Support

_Goal: load and render raster images._

- [ ] `Image` type (`src/graphics/image.zig`) — owns a `[]u32` ARGB pixel buffer + width/height
- [ ] `Image.loadPng(alloc, bytes)` — pure-Zig PNG decoder (deflate + filter passes)
- [ ] `Renderer.drawImage(image, dst_rect)` — nearest-neighbor scale blit via `drawImageRaw`
- [ ] `ImageWidget` — wraps `Image`, `preferredSize()` returns natural size, draw scales to rect
- [ ] Gallery: show zui logo PNG on Dashboard page
- [ ] Validated live: PNG loads and displays without distortion

## Milestone 17 — Font Descriptor + Style System

_Goal: per-widget font control; CSS-like style overrides._

- [ ] `Font` descriptor struct — family, weight (normal/semibold/bold), size, italic
- [ ] `Renderer.drawTextFont(text, x, y, color, font)` — selects GDI font matching descriptor
- [ ] `Style` struct — fg, bg, border, radius, padding, font; composable with `Style.merge(override)`
- [ ] Widgets accept optional `style: ?Style` override; fall back to theme defaults
- [ ] `Theme` extended: expose semantic tokens (heading_font, caption_font, card_bg, etc.)
- [ ] Validated live: Dashboard headings use semibold 22px, captions use 12px regular

## Milestone 18 — Animation System

_Goal: spring/ease-out transitions for all interactive states._

- [ ] `Animator(T)` generic — interpolates any numeric field with configurable easing
- [ ] Built-in easings: linear, ease-out, ease-in-out, spring (critically-damped)
- [ ] Button hover/press: colour + scale animated at 150ms ease-out
- [ ] Dialog open/close: fade-in + scale from 95% → 100% at 200ms ease-out
- [ ] Nav item active indicator: slide between items at 200ms ease-out
- [ ] Page transition: cross-fade content area at 150ms
- [ ] Validated live: all state transitions smooth at 60fps

## Milestone 19 — X11 Linux Backend

_Goal: `zig build run` works on Ubuntu/Arch with the software renderer._

- [ ] `src/platform/x11/window.zig` — `XOpenDisplay`, `XCreateWindow`, event loop via `XNextEvent`
- [ ] X11 SHM extension for zero-copy pixel blit (`XShmPutImage`)
- [ ] Map X11 key codes to `KeyCode` enum; map `ButtonPress`/`ButtonRelease` to mouse events
- [ ] `XIM`/`XIC` for Unicode text input
- [ ] `XGetWindowAttributes` for DPI (fall back to 96 if unavailable)
- [ ] Validate: `zig build run` on Linux shows Component Gallery, keyboard + mouse work

## Milestone 20 — Accessibility (UIA / AT-SPI)

_Goal: screen readers can enumerate the widget tree._

- [ ] `AccessNode` struct — role, name, value, bounds; emitted by each widget
- [ ] Win32: `IAccessible` / UI Automation provider stub registered on `WM_GETOBJECT`
- [ ] Linux: AT-SPI2 D-Bus interface (basic `accessible` + `component` interfaces)
- [ ] Focus events propagated to accessibility tree on focus change
- [ ] Validated: Narrator (Win32) / Orca (Linux) can read button and field labels

## Milestone 21 — macOS Cocoa Backend

_Goal: `zig build run` works on macOS with software renderer._

- [ ] `src/platform/cocoa/window.zig` — Objective-C interop via `@cImport` or raw `objc_msgSend`
- [ ] `NSWindow` + `NSView` with `drawRect:` for pixel blit
- [ ] `NSEvent` loop → zui `Event` translation
- [ ] Metal renderer stub (optional; software blit via `CGBitmapContext` is acceptable for M21)
- [ ] Validated: `zig build run` on macOS 14+ shows Component Gallery

## Milestone 22 — Vulkan Backend

_Goal: cross-platform GPU rendering via Vulkan._

- [ ] `src/graphics/vulkan/renderer.zig` — instance, physical device, logical device, swap chain
- [ ] Render pass: single colour attachment, present to swap chain
- [ ] Rect + rounded-rect pipeline: push constants for position/size/radius/colour
- [ ] Text: glyph atlas texture (Vulkan `VK_FORMAT_R8_UNORM`), quad draw per glyph
- [ ] `-Dbackend=vulkan` build option
- [ ] Validated live: Component Gallery renders on Vulkan on Win32 and Linux

---

## Backlog (post-1.0, not yet scheduled)

- Mica client-area compositing (requires DirectComposition or `UpdateLayeredWindow`)
- CSS-like style sheets (`.zss` parser, cascading selector model)
- Virtual/recycled ListView for large datasets (only render visible rows)
- Drag-and-drop (`IDropTarget` / `XdndProtocol`)
- Rich text (`TextDocument` model — bold, links, inline images)
- IME support for CJK text input
