$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath 'server/node_modules/ws')) {
    Push-Location server
    npm ci
    if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
    Pop-Location
}
Write-Host 'Open http://localhost:8080 in your browser. Ctrl+C stops the server.'
node server/index.mjs
