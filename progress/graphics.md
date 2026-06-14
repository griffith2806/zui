# Graphics Progress

## Status: Complete (M4 + M8 + M9 + M10)

### Done
- Software renderer (`src/graphics/software/renderer.zig`) — DIB pixel buffer, clear/fillRect/drawText/drawTextScaled
- 8×8 VGA bitmap font (`src/graphics/software/font.zig`) — ASCII 0x20–0x7E (fallback)
- OpenGL 3.3 core renderer (`src/graphics/opengl/renderer.zig`) — batched quad VAO/VBO, font atlas texture
- WGL context bootstrap (`src/platform/win32/gl_context.zig`)
- GL function pointer table (`src/graphics/opengl/gl.zig`)
- Font atlas 768×8 R8 (`src/graphics/opengl/font_atlas.zig`)
- Backend shim (`src/graphics/renderer.zig`) — comptime-selects backend
- `drawTextScaled(scale)` on both backends
- Build option `-Dbackend=software|opengl`
- `fillRoundRect(rect, radius, color)` in software renderer — pixel-accurate with alpha blending
- `fillRoundRect` in OpenGL renderer — dedicated SDF fragment shader
- **M10: GDI Segoe UI Variable typography** — `initGdi(dc)`, `CreateFontW` for scales 1–6,
  `TextOutW` on memory DC, `GetTextExtentPoint32W` for proportional measurement
- `textWidth(self, text)` and `textWidthScaled(self, text, scale)` as instance methods
- Font size table: `FONT_PX = [7]INT{ 0, 14, 22, 32, 44, 60, 80 }` (scales 1–6)

### Up Next (M7)
- Vulkan renderer backend
