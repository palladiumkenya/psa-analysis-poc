# stratify

PCA-based malaria stratification, ported from the **StratificationKEN** jamovi
module so the same analysis runs from a command line (in a script, on a
server, or in CI) without opening jamovi.

Given a CSV of administrative units and indicator columns it standardises the
indicators, takes the first principal component, cuts the scores at quantiles
and writes a stratified table. Optionally it joins the result to a shapefile
and draws the choropleth, exactly as the module's `.plot()` does.

## Two ways to run it

### 1. Locally installed R

The core needs **base R only**: no packages, no `install.packages`. That
means it also runs on the R bundled inside jamovi, which matters on a machine
that has jamovi but no separate R installation.

```powershell
.\run.ps1 -Test          # run the test suite
.\run.ps1 --help
```

```bash
./run.sh --test
./run.sh --help
```

`run.ps1` / `run.sh` locate R for you: `Rscript` on PATH first, then a
standalone R install, then jamovi's bundled R. They also add the installed
StratificationKEN module's bundled `sf` and `raster` to `R_LIBS`, so
`--shapefile` and `--map` work with nothing extra installed.

To skip the wrapper, call it directly:

```bash
Rscript bin/stratify.R --input data.csv --id ADM1_EN --vars "a,b,c"
```

### 2. Docker Compose

No local R at all. There is deliberately **no Dockerfile**; the core is base
R, so a stock pinned image runs it with nothing to build, and the optional
mapping uses `rocker/geospatial`, which already ships `sf`/`raster`/GDAL.

```bash
docker compose run --rm test                 # test suite
docker compose run --rm stratify --help
```

Three services:

| Service | Image | For |
|---|---|---|
| `stratify` | `r-base:4.3.2` | core CSV → CSV |
| `map` | `rocker/geospatial:4.3.2` | core plus `--shapefile` / `--map` |
| `test` | `r-base:4.3.2` | the test suite |

`r-base:4.3.2` is the same R version jamovi 2.5.3.0 bundles, so results match
the module exactly. Mounts: this project at `/app`, the surrounding malaria
project at `/data` (both read-only), and `./out` at `/out` for results.

## Examples

Stratify one year of county data:

```bash
Rscript bin/stratify.R \
  --input ../Data/Mappable/County_2026_mappable.csv \
  --id ADM1_EN \
  --vars "Incidence of Outpatient Malaria (per 1000 population),Malaria Test Positivity Rate - Overall,Confirmed Malaria cases Per 1000 Population" \
  --output out/strata_2026.csv
```

Pick a year out of a multi-year panel and draw the map:

```bash
Rscript bin/stratify.R \
  --input ../Data/county_panel.csv --filter Year=2026 \
  --id ADM1_EN --vars "...,...,..." \
  --output out/strata_2026.csv \
  --shapefile ../Data/Admin_1/County_boundaries.shp \
  --map out/map_2026.png
```

Same thing under Compose:

```bash
docker compose run --rm map \
  --input /data/Data/Mappable/County_2026_mappable.csv \
  --id ADM1_EN --vars "...,...,..." \
  --output /out/strata_2026.csv \
  --shapefile /data/Data/Admin_1/County_boundaries.shp \
  --map /out/map_2026.png
```

Forgotten the column names? `--list-columns` prints them.

## Options

| Option | Meaning |
|---|---|
| `--input FILE` | Input CSV; an Excel UTF-8 BOM is handled |
| `--id COLUMN` | Column identifying each unit, e.g. `ADM1_EN` |
| `--vars COL,...` | Indicator columns, comma separated |
| `--output FILE` | Results CSV (default: stdout) |
| `--groups N` | Number of strata (default 5) |
| `--digits N` | Decimals to round PC1 to before cutting (default 1) |
| `--orient MODE` | `asc` (default), `desc`, or `module`; see below |
| `--orient-by COLUMN` | Reference column for orientation (default: first of `--vars`) |
| `--filter COL=VALUE` | Keep matching rows; repeatable |
| `--shapefile FILE` | Join to this `.shp` and draw a choropleth |
| `--map FILE.png` | Where to write the map |
| `--shp-out FILE.shp` | Also write the joined shapefile |
| `--list-columns` | Print column names and exit |

The results table is your input plus `PCA_score`, `Stratum` and
`Stratum_label`. The summary (variance explained, loadings, units per
stratum) goes to stderr, so piping stdout to a file gives a clean CSV.

## Fidelity to the jamovi module

`tests/run_tests.R` includes a golden comparison: run with `--orient module`
on the 2026 county extract, the PC1 scores and all 47 strata are **identical**
to what the jamovi module produces. The fixtures are in `tests/data/`.

Several R defaults the module relies on are load-bearing and are reproduced
deliberately, each pinned by a test:

- `prcomp(scale. = TRUE)` scales by the **sample** sd (n−1 denominator).
- `quantile()` uses **type 7**.
- `round()` is **half-to-even**.
- `cut()` is right-closed and excludes the lowest break, so the minimum score
  returns `NA`; the module then forces those to stratum 1. Same result, but
  by way of an `NA`.

## One deliberate difference: the PC1 sign

The module does `PCA_results$x <- -1 * PCA_results$x`. The sign LAPACK gives
PC1 is arbitrary, so multiplying it by a constant is reproducible for one
dataset but **not comparable between datasets**, and it does flip in
practice. On the older demo data the highest-burden counties landed in
stratum 5 (red); on the 2026 extract the same code puts them in stratum 1
(dark green), silently reversing the map's colour scale.

So `--orient` defaults to `asc`, which anchors the sign to a reference column
(by default the first `--vars` entry, normally incidence):

- `asc`: PC1 rises with the reference; **the top stratum is the highest
  burden**. Stable across datasets. The default.
- `desc`: the reverse; stratum 1 is the highest burden.
- `module`: reproduce jamovi bit-for-bit, arbitrary sign included. Use this
  to check results against the module, not for new analysis.

Because of this, default output will not match the module's stratum
*numbering* on data where the module's sign happened to be inverted: the
partition is the same, the labels run the other way. Two tests pin exactly
this.

A caveat the orientation does not fix: `--orient-by` assumes higher is worse.
If your reference indicator runs the other way (coverage, say), pass a burden
indicator to `--orient-by` instead, or use `desc`.

## Things to watch

- **Multi-year panels.** There is no year handling, matching the module: every
  row is treated as its own unit, so five years of 47 counties become 235
  units. Use `--filter Year=2026`.
- **The join column must be identical on both sides.** `--id` names one column
  looked up in both the CSV and the shapefile; this is the module's
  constraint, not an added one. If your data says `County` and the shapefile
  says `ADM1_EN`, rename one.
- **Unmatched polygons.** The module paints shapefile features with no
  matching data as the last stratum, so "no data" looks like a real result.
  This port does the same for fidelity, but warns with a count.

## Layout

```
stratify/
├── bin/stratify.R        CLI
├── R/core.R              PCA + strata (base R only)
├── R/map.R               optional choropleth (needs sf, raster)
├── tests/run_tests.R     test suite, base R, no testthat
├── tests/data/           golden fixtures from the jamovi module
├── docker-compose.yml    stratify / map / test services
├── run.ps1               local-R runner, Windows
└── run.sh                local-R runner, Linux/macOS
```
