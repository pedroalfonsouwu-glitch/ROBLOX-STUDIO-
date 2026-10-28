$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$converted = & python (Join-Path $PSScriptRoot 'convert_cc0_obj.py') --stdout
if ($LASTEXITCODE -ne 0) { throw 'Falló la conversión OBJ' }
$result = ConvertFrom-Json -InputObject ($converted -join "`n")
$encoding = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'assets\roblox') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $projectRoot 'assets\roblox\Tree.rbxmx'), $result.xml, $encoding)
[IO.File]::WriteAllText((Join-Path $projectRoot 'assets\conversion.json'), ($result.report | ConvertTo-Json), $encoding)
$result.report | Format-List
