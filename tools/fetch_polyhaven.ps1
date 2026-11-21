# Lädt die Poly-Haven-Bestände für den Stiltest nach assets/external/polyhaven/ (nicht im Repository).
# Alle Poly-Haven-Bestände stehen unter CC0 (gemeinfrei): https://polyhaven.com/license
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\fetch_polyhaven.ps1

param(
    [string]$ModelResolution = "1k",
    [string]$TextureResolution = "2k"
)

$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot "..\assets\external\polyhaven"
$models = @("island_tree_02", "shrub_04", "shrub_02", "rock_moss_set_02", "boulder_01", "rock_07", "grass_medium_02")
$textures = @("rocky_terrain_02", "aerial_grass_rock", "brown_mud_leaves_01", "aerial_rocks_02", "mossy_rock", "coast_sand_01",
    "rock_boulder_dry", "withered_grass", "river_small_rocks", "bark_brown_02")

function Save-File($url, $target) {
    if (Test-Path $target) { return }
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $target -TimeoutSec 600
}

$log = @()
foreach ($id in $models) {
    $files = (Invoke-WebRequest -UseBasicParsing "https://api.polyhaven.com/files/$id").Content | ConvertFrom-Json
    $gltf = $files.gltf.$ModelResolution.gltf
    $dir = Join-Path $root "models\$id"
    Save-File $gltf.url (Join-Path $dir "$id.gltf")
    $size = $gltf.size
    foreach ($p in $gltf.include.PSObject.Properties) {
        Save-File $p.Value.url (Join-Path $dir $p.Name)
        $size += $p.Value.size
    }
    $info = (Invoke-WebRequest -UseBasicParsing "https://api.polyhaven.com/info/$id").Content | ConvertFrom-Json
    $log += [pscustomobject]@{ id = $id; kind = "model"; resolution = $ModelResolution; bytes = $size; polycount = $info.polycount; authors = ($info.authors.PSObject.Properties.Name -join ", "); license = "CC0"; source = "https://polyhaven.com/a/$id" }
    Write-Host ("Modell {0}: {1:N1} MB" -f $id, ($size / 1MB))
}
foreach ($id in $textures) {
    $files = (Invoke-WebRequest -UseBasicParsing "https://api.polyhaven.com/files/$id").Content | ConvertFrom-Json
    $dir = Join-Path $root "textures\$id"
    $size = 0
    foreach ($map in @("Diffuse", "nor_gl", "arm")) {
        $entry = $files.$map.$TextureResolution.jpg
        if ($null -eq $entry) { continue }
        Save-File $entry.url (Join-Path $dir ("{0}_{1}.jpg" -f $id, $map.ToLower()))
        $size += $entry.size
    }
    $info = (Invoke-WebRequest -UseBasicParsing "https://api.polyhaven.com/info/$id").Content | ConvertFrom-Json
    $log += [pscustomobject]@{ id = $id; kind = "texture"; resolution = $TextureResolution; bytes = $size; polycount = 0; authors = ($info.authors.PSObject.Properties.Name -join ", "); license = "CC0"; source = "https://polyhaven.com/a/$id" }
    Write-Host ("Textur {0}: {1:N1} MB" -f $id, ($size / 1MB))
}
$log | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $root "sources.json")
