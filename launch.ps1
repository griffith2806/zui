# Build and launch zui for quick live testing.
# Usage: .\launch.ps1            # build + launch (kills any running instance first)
#        .\launch.ps1 -NoBuild   # launch last built binary without rebuilding

param([switch]$NoBuild)

$exe = "zig-out\bin\zui.exe"

# Kill any running instance so the new one can take the window title
Get-Process -Name "zui" -ErrorAction SilentlyContinue | Stop-Process -Force

if (-not $NoBuild) {
    Write-Host "Building..." -ForegroundColor Cyan
    zig build
    if ($LASTEXITCODE -ne 0) { Write-Host "Build failed" -ForegroundColor Red; exit 1 }
}

Write-Host "Launching $exe ..." -ForegroundColor Green
Start-Process -FilePath $exe
