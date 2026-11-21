# Erzeugt Bildbestände mit Higgsfield und lädt sie nach assets/target/source/ (nicht im Repository).
# Jede Erzeugung wird mit Anweisung, Auftragsnummer und Adresse in generated.json festgehalten.
# KI-Erzeugung ist nicht wiederholbar – das Protokoll hält fest, woher jedes Bild stammt.
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\higgsfield_assets.ps1 [-Only name1,name2]

param([string[]]$Only = @())

$ErrorActionPreference = "Stop"
$hf = "$env:LOCALAPPDATA\Programs\higgsfield\higgsfield.exe"
$out = Join-Path $PSScriptRoot "..\assets\target\source"
New-Item -ItemType Directory -Force $out | Out-Null
$logPath = Join-Path $out "generated.json"
$log = @()
if (Test-Path $logPath) { $log = @(Get-Content $logPath -Raw | ConvertFrom-Json) }

$jobs = @(
    @{ name = "rock_reference"; aspect = "4:3"; background = "opaque";
       prompt = "A single large weathered grey granite rock ledge with smooth rounded edges and a flat sloping top, covered with patches of yellow-green and pale grey lichen and a few small moss tufts, isolated on a plain pure white background, three-quarter view from slightly above, soft even overcast daylight, photorealistic product photo, the whole rock visible, no ground, no grass, no cast shadow" },
    @{ name = "granite_lichen_texture"; aspect = "1:1"; background = "opaque";
       prompt = "Seamless tileable texture, straight top-down view of a grey granite rock surface with natural speckles, covered with irregular patches of yellow-green and pale grey crustose lichen and a few dark cracks, flat even diffuse lighting, no shadows, no perspective, photorealistic, high detail, fills the whole square" },
    @{ name = "grass_atlas"; aspect = "1:1"; background = "transparent";
       prompt = "Texture atlas for a real-time game engine: a 4 by 2 grid of eight separate tufts of wild meadow grass seen from the side, thin natural blades, some with seed heads, fresh yellow-green to warm green with a few dry golden blades, each tuft standing upright and filling its own cell, the base of every tuft touching the bottom edge of its cell, isolated on a fully transparent background, soft even daylight, photorealistic, no text" },
    @{ name = "flower_atlas"; aspect = "1:1"; background = "transparent";
       prompt = "Texture atlas for a real-time game engine: a 4 by 2 grid of eight separate clumps of European wildflowers seen from the side with their stems and a few leaves: yellow buttercups, white yarrow, purple loosestrife spikes, white ox-eye daisies, pink clover, blue cornflowers, yellow hawkweed, purple knapweed, each clump standing upright in its own cell with the stems touching the bottom edge, isolated on a fully transparent background, soft even daylight, photorealistic, no text" },
    @{ name = "rock_reference_2"; aspect = "4:3"; background = "opaque";
       prompt = "A single large weathered grey granite shore rock with a tall rounded side, a steep cracked front face and a sloping top with small moss cushions, patches of yellow-green and pale grey lichen, isolated on a plain pure white background, three-quarter view from slightly above, soft even overcast daylight, photorealistic product photo, the whole rock visible, no ground, no water, no cast shadow" },
    @{ name = "leaf_atlas_sunlit"; aspect = "1:1"; background = "transparent";
       prompt = "Texture atlas for a real-time game engine: a 2x2 grid of four separate leafy branch clusters of European oak and beech trees in bright summer sunlight, seen from above, dense overlapping leaves, warm sunlit yellow-green leaves with lighter edges and some darker green leaves underneath, natural and fresh, each cluster fills most of its own quadrant without touching the others, isolated on a fully transparent background, photorealistic, no text" },
    @{ name = "shrub_leaf_atlas"; aspect = "1:1"; background = "transparent";
       prompt = "Texture atlas for a real-time game engine: a 2 by 2 grid of four separate dense twig clusters of a small-leaved European shrub (hawthorn and blackthorn), many small dark green and fresh green leaves, seen from directly above, each cluster fills most of its quadrant without touching the others, soft even diffuse lighting, no cast shadows, isolated on a fully transparent background, photorealistic, no text" }
)

foreach ($job in $jobs) {
    if ($Only.Count -gt 0 -and $Only -notcontains $job.name) { continue }
    $file = Join-Path $out ($job.name + ".png")
    if (Test-Path $file) { Write-Host "vorhanden: $($job.name)"; continue }
    Write-Host "erzeuge: $($job.name)"
    $json = & $hf generate create gpt_image_2_6 --prompt $job.prompt --quality high --resolution 2k `
        --aspect_ratio $job.aspect --background $job.background --wait --json 2>&1 | Out-String
    $result = ($json | ConvertFrom-Json)[0]
    Invoke-WebRequest -UseBasicParsing $result.result_url -OutFile $file -TimeoutSec 300
    $log += [pscustomobject]@{ name = $job.name; prompt = $job.prompt; job_id = $result.id; url = $result.result_url;
        model = "gpt_image_2_6"; quality = "high"; resolution = "2k"; credits = 2; created = $result.created_at }
    $log | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $logPath
}
& $hf account status
