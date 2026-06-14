# Graphics Progress

## Status: Complete (M4)

### Done
- Software renderer (`src/graphics/software/renderer.zig`) — DIB pixel buffer, clear/fillRect/drawText, BitBlt to window
- 8×8 VGA bitmap font (`src/graphics/software/font.zig`) — ASCII 0x20–0x7E, MSB = leftmost pixel
- **OpenGL 3.3 core renderer** (`src/graphics/opengl/renderer.zig`)
  - WGL context creation with core profile bootstrap (`src/platform/win32/gl_context.zig`)
  - GL function pointer table loaded at runtime via wglGetProcAddress (`src/graphics/opengl/gl.zig`)
  - Font atlas texture 768×8 R8 (`src/graphics/opengl/font_atlas.zig`)
  - Batched quad renderer: solid rects (UV < 0 = solid) + text quads (UV samples atlas)
  - Vertex layout: pos(2) + uv(2) + color(4), single VAO/VBO, DYNAMIC_DRAW
  - Up to 4096 quads per flush; auto-flushes on overflow
- Backend shim (`src/graphics/renderer.zig`) — comptime selects software or opengl
- Build option `-Dbackend=software|opengl` wired in `build.zig`
- Both backends validated live: same dashboard renders correctly in both modes

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next (M7)
- Vulkan renderer backend
