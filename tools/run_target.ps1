# Zielszene messen und neben das Zielbild stellen. Bilder und Messwerte in docs/ziel/.
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\run_target.ps1 [-Views ziel,nah] [-Tag runde1]

param(
    [string]$Godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Position = "2000,60",
    [string[]]$Views = @("ziel"),
    [string]$Tag = ""
)

$project = Resolve-Path (Join-Path $PSScriptRoot "..")
$out = Join-Path $project "docs\ziel"
New-Item -ItemType Directory -Force $out | Out-Null

& $Godot --headless --path $project --import 2>&1 | Out-Null
$changed = 0
foreach ($f in Get-ChildItem (Join-Path $project "assets") -Recurse -Filter "*nor_gl*.import") {
    $text = Get-Content $f.FullName
    if ($text -match '^compress/normal_map=0') {
        $text -replace '^compress/normal_map=0', 'compress/normal_map=1' | Set-Content -Encoding utf8 $f.FullName
        $changed++
    }
}
if ($changed -gt 0) { & $Godot --headless --path $project --import 2>&1 | Out-Null }

Add-Type -AssemblyName System.Drawing
foreach ($view in $Views) {
    $name = if ($Tag) { "${view}_$Tag" } else { $view }
    & $Godot --position $Position --resolution 1440x810 --path $project res://scenes/target_scene.tscn -- `
        "--ansicht=$view" "--bench=$out\$name.json" "--screenshot=$out\$name.jpg" 2>&1 |
        Select-String -Pattern "ERROR|SCRIPT ERROR" | Select-Object -First 5
    $r = Get-Content "$out\$name.json" -Raw | ConvertFrom-Json
    "{0,-6}: {1,6:N1} Bilder/s  (95 % <= {2,5:N1} ms)  {3,9:N0} Dreiecke  {4,4} Aufrufe  Grafikspeicher {5,5:N0} MB  Aufbau {6,6:N0} ms" -f `
        $view, $r.fps_avg, $r.frame_ms_p95, $r.primitives, $r.draw_calls, $r.video_mem_mb, $r.build_ms
    if ($view -eq "ziel") {
        # Neben das Zielbild stellen.
        $target = [System.Drawing.Image]::FromFile((Join-Path $project "docs\stiltest\zielbild_higgsfield.jpg"))
        $shot = [System.Drawing.Image]::FromFile("$out\$name.jpg")
        $pair = New-Object System.Drawing.Bitmap 1440, 1620
        $g = [System.Drawing.Graphics]::FromImage($pair)
        $g.DrawImage($target, 0, 0, 1440, 810)
        $g.DrawImage($shot, 0, 810, 1440, 810)
        $g.DrawString("Zielbild", (New-Object System.Drawing.Font 'Arial', 16), [System.Drawing.Brushes]::White, 12, 8)
        $g.DrawString("Godot", (New-Object System.Drawing.Font 'Arial', 16), [System.Drawing.Brushes]::White, 12, 818)
        $pair.Save("$out\vergleich_$name.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $g.Dispose(); $pair.Dispose(); $target.Dispose(); $shot.Dispose()
    }
}
