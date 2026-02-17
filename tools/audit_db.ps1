Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IdsFromFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    $content = Get-Content -LiteralPath $Path -Raw

    foreach ($m in [regex]::Matches($content, $Pattern)) {
        $null = $ids.Add([int]$m.Groups['id'].Value)
    }

    return $ids
}

function Format-IdList {
    param([int[]]$Ids)
    if (-not $Ids -or $Ids.Count -eq 0) { return "(none)" }
    return ($Ids | Sort-Object) -join ', '
}

$addonDir = Resolve-Path (Join-Path $PSScriptRoot '..')
$xpFiles = Get-ChildItem -LiteralPath $addonDir -File -Filter 'fr0z3nUI_AutoOpenXP*.lua'

$xpXX = $xpFiles | Where-Object { $_.Name -eq 'fr0z3nUI_AutoOpenXPXX.lua' } | Select-Object -First 1
$xpTR = $xpFiles | Where-Object { $_.Name -eq 'fr0z3nUI_AutoOpenXPTR.lua' } | Select-Object -First 1
if (-not $xpXX) { throw "Missing fr0z3nUI_AutoOpenXPXX.lua in $addonDir" }
if (-not $xpTR) { throw "Missing fr0z3nUI_AutoOpenXPTR.lua in $addonDir" }

$items = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($f in $xpFiles) {
    if ($f.Name -in @('fr0z3nUI_AutoOpenXPXX.lua', 'fr0z3nUI_AutoOpenXPTR.lua')) { continue }

    $fileItems = Get-IdsFromFile -Path $f.FullName -Pattern 'ns\.items\[\s*(?<id>\d+)\s*\]'
    foreach ($id in $fileItems) { $null = $items.Add($id) }
}

$exclude = Get-IdsFromFile -Path $xpXX.FullName -Pattern 'ns\.exclude\[\s*(?<id>\d+)\s*\]'
$timed = Get-IdsFromFile -Path $xpTR.FullName -Pattern 'ns\.timed\[\s*(?<id>\d+)\s*\]'

# Sanity checks on the specialized DB files
$xpXXHasItems = [regex]::IsMatch((Get-Content -LiteralPath $xpXX.FullName -Raw), 'ns\.items\[\s*\d+\s*\]')
$xpTRHasItems = [regex]::IsMatch((Get-Content -LiteralPath $xpTR.FullName -Raw), 'ns\.items\[\s*\d+\s*\]')

$itemsInExclude = @()
foreach ($id in $items) { if ($exclude.Contains($id)) { $itemsInExclude += $id } }

$itemsInTimed = @()
foreach ($id in $items) { if ($timed.Contains($id)) { $itemsInTimed += $id } }

$problems = $false
Write-Host "FAO DB Audit" -ForegroundColor Cyan
Write-Host "- Whitelist (ns.items) IDs: $($items.Count)"
Write-Host "- Exclude (ns.exclude) IDs:  $($exclude.Count)"
Write-Host "- Timed (ns.timed) IDs:     $($timed.Count)"
Write-Host ""

if ($xpXXHasItems) {
    Write-Host "ERROR: XPXX contains ns.items entries (should be ns.exclude only)." -ForegroundColor Red
    $problems = $true
}

if ($xpTRHasItems) {
    Write-Host "WARN: XPTR contains ns.items entries (unexpected; timed DB should be ns.timed only)." -ForegroundColor Yellow
}

if ($itemsInExclude.Count -gt 0) {
    Write-Host "ERROR: Overlap ns.items ∩ ns.exclude:" -ForegroundColor Red
    Write-Host (Format-IdList -Ids $itemsInExclude)
    $problems = $true
}

if ($itemsInTimed.Count -gt 0) {
    Write-Host "ERROR: Overlap ns.items ∩ ns.timed:" -ForegroundColor Red
    Write-Host (Format-IdList -Ids $itemsInTimed)
    $problems = $true
}

if (-not $problems) {
    Write-Host "OK: No overlaps detected." -ForegroundColor Green
    exit 0
}

exit 1
