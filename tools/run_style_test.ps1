# Führt den Stiltest aus: A und B, je Arbeits- und Nahansicht.
# Bilder (JPG) und Messwerte (JSON) landen in docs/stiltest/.
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\run_style_test.ps1

param([string]$Godot = "C:\Users\Mattes\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe")

$project = Resolve-Path (Join-Path $PSScriptRoot "..")
$out = Join-Path $project "docs\stiltest"
New-Item -ItemType Directory -Force $out | Out-Null

# Normalenkarten als solche importieren (sonst wie Farbbilder komprimiert).
& $Godot --headless --path $project --import 2>&1 | Out-Null
$changed = 0
foreach ($f in Get-ChildItem (Join-Path $project "assets") -Recurse -Filter "*nor_gl*.import") {
    $text = Get-Content $f.FullName
    if ($text -match '^compress/normal_map=0') {
        $text -replace '^compress/normal_map=0', 'compress/normal_map=1' | Set-Content -Encoding utf8 $f.FullName
        $changed++
    }
}
# Laubmodelle ohne automatische Vereinfachung importieren: Godots LOD rechnet einzelne Blätter weg.
foreach ($id in "island_tree_02", "grass_medium_02") {
    $f = Join-Path $project "assets\external\polyhaven\models\$id\$id.gltf.import"
    $text = Get-Content $f
    if ($text -match '^meshes/generate_lods=true') {
        $text -replace '^meshes/generate_lods=true', 'meshes/generate_lods=false' | Set-Content -Encoding utf8 $f
        $changed++
    }
}
if ($changed -gt 0) { & $Godot --headless --path $project --import 2>&1 | Out-Null }

foreach ($variant in "A", "B") {
    foreach ($view in "arbeit", "nah") {
        $name = "$($variant.ToLower())_$view"
        & $Godot --path $project res://scenes/style_test.tscn -- "--variant=$variant" "--ansicht=$view" `
            "--bench=$out\$name.json" "--screenshot=$out\$name.jpg" "--overlay=nein" 2>&1 | Out-Null
        $r = Get-Content "$out\$name.json" -Raw | ConvertFrom-Json
        "{0} {1,-6}: {2,6:N1} Bilder/s  (95 % ≤ {3,5:N1} ms)  {4,9:N0} Dreiecke  {5,4} Aufrufe  Grafikspeicher {6,5:N0} MB  Laden {7,5:N0} ms" -f `
            $variant, $view, $r.fps_avg, $r.frame_ms_p95, $r.primitives, $r.draw_calls, $r.video_mem_mb, $r.load_ms
    }
}
