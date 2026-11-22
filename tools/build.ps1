# Fabrique le zip du mod FlowDrive.
# Usage : powershell -ExecutionPolicy Bypass -File tools\build.ps1
# Resultat : dist\FS25_FlowDrive.zip (a copier dans mods, jeu ferme) et dist\FS25_FlowDrive_<version>.zip

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mod = Join-Path $root 'FS25_FlowDrive'

[xml]$desc = Get-Content -Raw -Encoding UTF8 (Join-Path $mod 'modDesc.xml')
$version = $desc.modDesc.version
Write-Host "FlowDrive $version"

# 1. structure des fichiers Lua (si Node.js est installe)
$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -ne $node) {
    $luaFiles = Get-ChildItem (Join-Path $mod 'scripts') -Filter *.lua | ForEach-Object { $_.FullName }
    & node (Join-Path $PSScriptRoot 'luacheck_blocks.js') $luaFiles
    if ($LASTEXITCODE -ne 0) { throw 'Structure Lua incorrecte : zip non fabrique' }
} else {
    Write-Host 'Node.js absent : verification Lua sautee'
}

# 2. les fichiers XML doivent se lire
Get-ChildItem $mod -Recurse -Filter *.xml | ForEach-Object {
    try { [xml](Get-Content -Raw -Encoding UTF8 $_.FullName) | Out-Null }
    catch { throw "XML illisible : $($_.FullName)" }
}

# 3. zip, avec le contenu du mod a la racine
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist 'FS25_FlowDrive.zip'
if (Test-Path $zip) { Remove-Item $zip }
$items = Get-ChildItem $mod | ForEach-Object { $_.Name }
& "$env:SystemRoot\System32\tar.exe" -a -c -f $zip -C $mod $items
if ($LASTEXITCODE -ne 0) { throw 'Echec de la fabrication du zip' }
Copy-Item $zip (Join-Path $dist "FS25_FlowDrive_$version.zip") -Force
Write-Host "Zip pret : $zip"
