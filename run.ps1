<#
.SYNOPSIS
  Local-R run path for Windows.

.DESCRIPTION
  Finds an R installation and runs bin/stratify.R with whatever arguments you
  pass through. Looks for Rscript on PATH, then a standalone R install, then
  the R bundled inside jamovi -- which on a machine with jamovi but no
  separate R is the only one present.

  If the StratificationKEN jamovi module is installed, its bundled sf and
  raster are added to R_LIBS so --shapefile / --map work without installing
  anything.

.EXAMPLE
  .\run.ps1 --help
  .\run.ps1 --input ..\Data\Mappable\County_2026_mappable.csv --id ADM1_EN `
            --vars "Incidence of Outpatient Malaria (per 1000 population),Malaria Test Positivity Rate - Overall,Confirmed Malaria cases Per 1000 Population" `
            --output out\strata_2026.csv

.EXAMPLE
  .\run.ps1 -Test
#>
[CmdletBinding()]
param(
    [switch]$Test,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Rscript {
    $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $standalone = Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue |
                  Sort-Object FullName -Descending | Select-Object -First 1
    if ($standalone) { return $standalone.FullName }

    $jamovi = Get-ChildItem 'C:\Program Files\jamovi*\Frameworks\R\bin\Rscript.exe' -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1
    if ($jamovi) { return $jamovi.FullName }

    return $null
}

$rscript = Find-Rscript
if (-not $rscript) {
    Write-Error @'
No R installation found.

Install R from https://cran.r-project.org/bin/windows/base/, or use the
Docker path instead:

    docker compose run --rm stratify --help
'@
    exit 1
}
Write-Host "using R: $rscript" -ForegroundColor DarkGray

# Make the jamovi module's bundled sf/raster visible, for --shapefile/--map.
$libs = @()
$moduleLib = Join-Path $env:APPDATA 'jamovi\modules\StratificationKEN\R'
if (Test-Path $moduleLib) { $libs += $moduleLib }
$baseLib = Get-ChildItem 'C:\Program Files\jamovi*\Resources\modules\base\R' -Directory -ErrorAction SilentlyContinue |
           Sort-Object FullName -Descending | Select-Object -First 1
if ($baseLib) { $libs += $baseLib.FullName }
if ($libs.Count -gt 0) {
    $env:R_LIBS = ($libs -join ';')
    Write-Host "R_LIBS: $env:R_LIBS" -ForegroundColor DarkGray
}

if ($Test) {
    & $rscript (Join-Path $here 'tests\run_tests.R')
    exit $LASTEXITCODE
}

$script = Join-Path $here 'bin\stratify.R'
if ($Rest) { & $rscript $script @Rest } else { & $rscript $script "--help" }
exit $LASTEXITCODE
