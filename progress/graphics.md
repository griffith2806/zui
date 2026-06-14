# Graphics Progress

## Status: Complete (M2)

### Done
- Renderer interface (`src/graphics/software/renderer.zig`)
- Software backend: clear (fill buffer), fillRect, BGRA pixel format for Win32 DIB
- 8×8 VGA bitmap font (`src/graphics/software/font.zig`) — ASCII 0x20–0x7E
- drawText() — renders text using glyph bitmaps, MSB = leftmost pixel
- textWidth() — returns pixel width of a string
- Fixed DIB stride mismatch (AdjustWindowRect ensures client area = requested size)

### In Progress
_(nothing)_

### Blocked
_(nothing)_

### Up Next (Milestone 4)
- OpenGL 3.3 core renderer backend
- Font atlas (glyph rasterization → texture)
- Clip region support
- Draw image / blit
