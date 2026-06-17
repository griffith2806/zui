# Image Loading Progress

## Status: Complete

### Done
- `src/platform/win32/wic.zig` — WIC COM bindings (new file)
  - Runtime COM initialization via `CoInitializeEx` (ole32.dll)
  - `CoCreateInstance` → `IWICImagingFactory` (WindowsCodecs.dll, no import lib needed)
  - Full vtable declarations for `IWICImagingFactory`, `IWICBitmapDecoder`, `IWICBitmapSource`, `IWICFormatConverter`
  - `loadFileAsBgra(alloc, path, &w, &h)` — decodes any WIC-supported format (PNG, JPEG, BMP, TIFF, GIF, …) to pre-multiplied BGRA bytes
  - UTF-8 → UTF-16LE path conversion using `std.unicode.utf8ToUtf16Le`
  - Typed `WicError` error set; all COM HRESULTs mapped
- `src/graphics/image.zig` — three new public methods on `Image`
  - `Image.loadFile(alloc, path) !Image` — platform-dispatched; calls WIC on Windows, returns `error.NotImplemented` elsewhere
  - `Image.loadPng(alloc, path) !Image` — alias for `loadFile`
  - `Image.loadJpeg(alloc, path) !Image` — alias for `loadFile`
  - `Image.fromPremulBgra(alloc, bgra, w, h) !Image` — helper that converts BGRA byte buffer to 0xAARRGGBB u32 pixels (B↔R swap)
  - Tests for `fromPremulBgra` and `loadFile` (non-Windows skip guard)
- `src/root.zig` — `Image` was already exported; no change needed
- `zig build` — compiles clean (zero errors, zero warnings)
- `zig build test` — all tests pass

### Up Next
- WIC image loading in the OpenGL renderer (texture upload path)
- Vulkan texture pipeline (currently a no-op stub)
- Cross-platform fallback: a pure-Zig PNG/JPEG decoder for Linux/macOS
