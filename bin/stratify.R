#!/usr/bin/env Rscript
# Command-line front end for the StratificationKEN port.
#
#   Rscript bin/stratify.R --input data.csv --id ADM1_EN --vars "a,b,c"
#
# See README.md for the local-R and Docker Compose run paths.

suppressWarnings({
  .args_all <- commandArgs(trailingOnly = FALSE)
  .file_arg <- grep("^--file=", .args_all, value = TRUE)
  .here <- if (length(.file_arg))
    dirname(normalizePath(sub("^--file=", "", .file_arg[1])))
  else getwd()
})
source(file.path(.here, "..", "R", "core.R"), chdir = FALSE)
source(file.path(.here, "..", "R", "map.R"), chdir = FALSE)

USAGE <- "
stratify - PCA-based malaria stratification (port of the StratificationKEN
           jamovi module, runnable outside jamovi)

USAGE
  Rscript bin/stratify.R --input <FILE> --id <COLUMN> --vars <COL,COL,...> [OPTIONS]
  Rscript bin/stratify.R --input <FILE> --list-columns

REQUIRED
  --input <FILE>        Input CSV (an Excel UTF-8 BOM is handled)
  --id <COLUMN>         Column identifying each unit, e.g. ADM1_EN
  --vars <COL,...>      Indicator columns, comma separated

OPTIONS
  --output <FILE>       Write the results table here (default: stdout)
  --groups <N>          Number of strata (default: 5)
  --digits <N>          Decimals to round PC1 to before cutting (default: 1)
  --orient <MODE>       asc | desc | module   (default: asc)
                          asc    - top stratum = highest burden (stable)
                          desc   - stratum 1   = highest burden
                          module - reproduce jamovi exactly (arbitrary sign)
  --orient-by <COLUMN>  Reference column for asc/desc (default: first of --vars)
  --filter <COL=VALUE>  Keep only matching rows. Repeatable. Use this to pick
                        one year out of a multi-year panel - the module has no
                        year handling and would treat each year as a unit.
  --shapefile <FILE>    Join to this .shp and draw a choropleth
  --map <FILE.png>      Where to write the map (implies --shapefile)
  --shp-out <FILE.shp>  Also write the joined shapefile
  --list-columns        Print column names and exit
  --help                Show this help
"

args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || any(args %in% c("-h", "--help"))) { cat(USAGE); quit(status = 0) }

get_opt <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (!length(i)) return(default)
  if (i[1] == length(args)) stop(flag, " needs a value", call. = FALSE)
  args[i[1] + 1]
}
get_all <- function(flag) {
  i <- which(args == flag)
  if (!length(i)) return(character(0))
  args[i + 1]
}
has_flag <- function(flag) any(args == flag)

input <- get_opt("--input")
if (is.null(input)) stop("--input is required (see --help)", call. = FALSE)
if (!file.exists(input)) stop("no such file: ", input, call. = FALSE)

read_input <- function(path) {
  d <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE,
                       fileEncoding = "UTF-8-BOM")
  # Drop fully blank trailing rows, which Excel exports love to add.
  keep <- rowSums(!is.na(d) & trimws(as.matrix(sapply(d, as.character))) != "") > 0
  d[keep, , drop = FALSE]
}
dat <- read_input(input)

if (has_flag("--list-columns")) {
  cat(sprintf("%d columns, %d rows:\n", ncol(dat), nrow(dat)))
  cat(sprintf("  [%2d] %s\n", seq_along(names(dat)), names(dat)), sep = "")
  quit(status = 0)
}

# --filter COL=VALUE, repeatable
for (f in get_all("--filter")) {
  parts <- strsplit(f, "=", fixed = TRUE)[[1]]
  if (length(parts) < 2) stop("--filter expects COL=VALUE, got: ", f, call. = FALSE)
  col <- parts[1]; val <- paste(parts[-1], collapse = "=")
  if (!col %in% names(dat)) stop("--filter: no such column: ", col, call. = FALSE)
  before <- nrow(dat)
  dat <- dat[as.character(dat[[col]]) == val, , drop = FALSE]
  message(sprintf("filter %s==%s: %d -> %d rows", col, val, before, nrow(dat)))
}

id <- get_opt("--id")
if (is.null(id)) stop("--id is required (see --help)", call. = FALSE)
vars_raw <- get_opt("--vars")
if (is.null(vars_raw)) stop("--vars is required (see --help)", call. = FALSE)
vars <- trimws(strsplit(vars_raw, ",", fixed = TRUE)[[1]])
vars <- vars[nzchar(vars)]

groups <- as.integer(get_opt("--groups", "5"))
digits <- as.integer(get_opt("--digits", "1"))
orient <- get_opt("--orient", "asc")
orient_by <- get_opt("--orient-by")

res <- stratify_pca(dat, id_col = id, vars = vars, groups = groups,
                    digits = digits, orient = orient, orient_by = orient_by)

out_path <- get_opt("--output")
if (is.null(out_path)) {
  utils::write.csv(res$table, stdout(), row.names = FALSE)
} else {
  utils::write.csv(res$table, out_path, row.names = FALSE)
}

# Summary on stderr so stdout stays a clean CSV when piped.
msg <- function(...) message(sprintf(...))
msg("units: %d   variables: %d", nrow(res$table), length(vars))
msg("PC1 explains %.1f%% of total variance", 100 * res$explained)
if (res$orientation$mode == "module") {
  msg("orientation: module (LAPACK sign x -1; arbitrary, not comparable across datasets)")
} else {
  msg("oriented on '%s': stratum %d = %s values", res$orientation$reference,
      groups, if (res$orientation$mode == "asc") "highest" else "lowest")
}
msg("loadings:")
for (i in seq_along(vars)) msg("  %+.4f  %s", res$loadings[i], vars[i])
msg("units per stratum: %s",
    paste(sprintf("%d:%d", seq_len(groups), res$counts), collapse = "  "))
if (!is.null(out_path)) msg("written: %s", out_path)

shapefile <- get_opt("--shapefile")
map_png <- get_opt("--map")
shp_out <- get_opt("--shp-out")
if (!is.null(map_png) && is.null(shapefile))
  stop("--map needs --shapefile", call. = FALSE)
if (!is.null(shapefile)) {
  render_map(res, id_col = id, shapefile = shapefile, png_path = map_png,
             shp_out = shp_out, groups = groups,
             title = sprintf("Stratification (%d strata)", groups))
  if (!is.null(map_png)) msg("map written: %s", map_png)
  if (!is.null(shp_out)) msg("shapefile written: %s", shp_out)
}
