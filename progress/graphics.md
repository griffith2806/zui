# Graphics Progress

## Status: Complete (M4 + M8 + M9 + M10 + M13 + gap-close)

### Done
- Software renderer (`src/graphics/software/renderer.zig`) — DIB pixel buffer, clear/fillRect/drawText/drawTextScaled/fillRoundRect
- drawImageRaw(pixels, src_w, src_h, dst) — alpha-compositing blit in 0xAARRGGBB format
- Image type (`src/graphics/image.zig`) — fromRgba(), fromColor(), deinit()
- 8×8 VGA bitmap font (`src/graphics/software/font.zig`) — ASCII 0x20–0x7E (fallback)
- OpenGL 3.3 core renderer (`src/graphics/opengl/renderer.zig`) — batched quad VAO/VBO, font atlas, SDF rounded rects
- WGL context bootstrap, GL function pointer table, font atlas
- Backend shim (`src/graphics/renderer.zig`) — comptime-selects backend
- GDI Segoe UI Variable typography on Win32 software backend (scales 1–6)
- M13: Renderer.setClip(?Rect) / clearClip() — logical clip rect; all draw calls (fillRect, fillRoundRect, drawImageRaw, bitmap text) clip to the active rect; deferred GDI TextOut uses IntersectClipRect/SelectClipRgn on the screen DC

### Up Next
- drawImageRaw in OpenGL backend (texture upload + quad render)
- Vulkan renderer backend (M7)
