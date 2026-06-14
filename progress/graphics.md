# Graphics Progress

## Status: Complete (M4 + M8 + M9 + M10 + M13 + M22 + gap-close)

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
- M22: Vulkan renderer backend (`src/graphics/vulkan/renderer.zig`) — compiles with `-Dbackend=vulkan`
  - No Vulkan SDK headers required: all VkXxx types declared as Zig extern structs / opaque handles
  - Runtime DLL loading: LoadLibraryA("vulkan-1.dll") + vkGetInstanceProcAddr; no .lib import at link time
  - Real Vulkan initialization: VkInstance, Win32 surface, physical device selection, VkDevice, swapchain, image views, render pass, push-constant pipeline layout, graphics pipeline, framebuffers, command pool + buffers, semaphores + fences
  - Embedded minimal SPIR-V stubs for vertex/fragment shaders (replace with full compiled shaders before GPU use)
  - Rect draw queue: fillRect / fillRoundRect batch into draw_cmds[]; present() records + submits a command buffer per frame using push constants (x,y,w,h,r,g,b,a) and the full-screen triangle trick
  - Text stubs (drawText / textWidth return 0 / no-op) — Vulkan glyph atlas deferred
  - Image stubs (drawImage / drawImageRaw no-op) — Vulkan texture pipeline deferred
  - build.zig: Backend enum extended to `{ software, opengl, vulkan }`
  - app.zig: `.vulkan` branch added to init / deinit / syncSize / present

### Up Next
- drawImageRaw in OpenGL backend (texture upload + quad render)
- Vulkan: replace SPIR-V stubs with real compiled shaders (requires glslangValidator / shaderc)
- Vulkan: swapchain recreation on resize (vkAcquireNextImageKHR VK_ERROR_OUT_OF_DATE_KHR)
- Vulkan: glyph atlas pipeline for text rendering
