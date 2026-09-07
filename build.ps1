param([string]$Godot = 'C:/Users/tetra/softs/godot/Godot.exe')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
New-Item -ItemType Directory -Force build/web,build/windows | Out-Null
Set-Content build/.gdignore ''
& $Godot --headless --path $PSScriptRoot --export-release Web | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Web export failed' }
& $Godot --headless --path $PSScriptRoot --export-release 'Windows Desktop' | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
foreach ($releaseDir in @('build/web','build/windows')) {
    Copy-Item -LiteralPath assets/OFL.txt -Destination ($releaseDir + '/FONT_LICENSE.txt')
    Copy-Item -LiteralPath assets/GODOT_LICENSE.txt -Destination $releaseDir
    Copy-Item -LiteralPath assets/GODOT_COPYRIGHT.txt -Destination $releaseDir
}
