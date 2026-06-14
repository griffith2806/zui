# zui Debug

Rebuild zui, launch it, and take a live screenshot so you can see the current visual state of the app. Optionally navigate to a specific page.

## Usage
`/zui-debug [page]`

Optional `page` argument: `dashboard`, `controls`, `inputs`, `overlays`, `colors`, `layout`, `about`

## Steps

1. **Kill any running zui.exe** so the build isn't blocked by a file lock:
   ```powershell
   Get-Process -Name "zui" -ErrorAction SilentlyContinue | Stop-Process -Force
   ```

2. **Rebuild** the project:
   ```
   zig build
   ```
   If the build fails, stop here and show the error — do not proceed to launch.

3. **Launch** the new binary in the background:
   ```powershell
   Start-Process -FilePath "zig-out\bin\zui.exe"
   ```

4. **Wait 2 seconds** for the window to appear: `mcp__ui-automation__wait { seconds: 2 }`

5. **Focus** the window: `mcp__ui-automation__focus_window { title: "Component Gallery" }`

6. **Maximize** the window: `mcp__ui-automation__key_press { keys: "win+up" }`, then wait 0.5s.

7. **Navigate to page** (if `$ARGUMENTS` is provided):
   The nav items are at physical coordinates. The page order is:
   - dashboard: y=306
   - controls: y=394
   - inputs: y=438  (actually nav index 2, y = 2*(48+8+2*44+19)+68 = 394... recalculate as needed)

   Use this formula for nav item i (0-indexed):
   - Logical y_center = 48 + 8 + i*44 + 19 = 75 + i*44
   - Physical y = 2 * logical_y + 68
   - Physical x = 107

   Page → index: dashboard=0, controls=1, inputs=2, overlays=3, colors=4, layout=5, about=6

   Click the nav item then wait 0.5s.

8. **Screenshot** with `mcp__ui-automation__screenshot` and show the result.

9. **Report** what you see: layout issues, visual bugs, truncated text, wrong colors, etc. Compare against the WPF UI Gallery if available.

## Coordinate reference
- All MCP click coordinates are **physical screen pixels** (2× at 200% DPI)
- Screenshots are at **logical resolution** (half the physical size)
- To convert: `phys_x = 2 * logical_x`, `phys_y = 2 * logical_y + 68` (68 = physical window top offset)
- Nav physical x = 107 for all items
