# Graphics Progress

## Status: Complete (M4 + M8 + M9)

### Done
- Software renderer (`src/graphics/software/renderer.zig`) — DIB pixel buffer, clear/fillRect/drawText/drawTextScaled
- 8×8 VGA bitmap font (`src/graphics/software/font.zig`) — ASCII 0x20–0x7E
- OpenGL 3.3 core renderer (`src/graphics/opengl/renderer.zig`) — batched quad VAO/VBO, font atlas texture
- WGL context bootstrap (`src/platform/win32/gl_context.zig`)
- GL function pointer table (`src/graphics/opengl/gl.zig`)
- Font atlas 768×8 R8 (`src/graphics/opengl/font_atlas.zig`)
- Backend shim (`src/graphics/renderer.zig`) — comptime-selects backend
- `drawTextScaled(scale)` on both backends — integer-scaled glyphs for headings
- Build option `-Dbackend=software|opengl`
- `fillRoundRect(rect, radius, color)` in software renderer — pixel-accurate SDF with alpha blending
- `fillRoundRect` in OpenGL renderer — dedicated SDF fragment shader (GLSL 3.30 `smoothstep` AA)
- `uniform1f` / `uniform4f` added to `gl.Gl` for SDF uniforms

### Up Next (M7)
- Vulkan renderer backend
