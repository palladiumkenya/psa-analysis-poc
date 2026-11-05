#!/usr/bin/env bash
# Local-R run path for Linux and macOS. See run.ps1 for Windows.
#
#   ./run.sh --help
#   ./run.sh --test
#   ./run.sh --input ../Data/Mappable/County_2026_mappable.csv --id ADM1_EN \
#            --vars "a,b,c" --output out/strata.csv
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_rscript() {
  if command -v Rscript >/dev/null 2>&1; then command -v Rscript; return; fi
  # macOS framework install
  local mac="/Library/Frameworks/R.framework/Resources/bin/Rscript"
  if [ -x "$mac" ]; then echo "$mac"; return; fi
  # jamovi's bundled R
  for p in /Applications/jamovi.app/Contents/Frameworks/R/bin/Rscript \
           /usr/lib/jamovi/Frameworks/R/bin/Rscript; do
    if [ -x "$p" ]; then echo "$p"; return; fi
  done
  return 1
}

if ! rscript="$(find_rscript)"; then
  cat >&2 <<'EOF'
No R installation found.

Install R from https://cran.r-project.org/, or use the Docker path instead:

    docker compose run --rm stratify --help
EOF
  exit 1
fi
echo "using R: $rscript" >&2

# Expose jamovi's bundled sf/raster for --shapefile / --map, if present.
for lib in "$HOME/Library/Application Support/jamovi/modules/StratificationKEN/R" \
           "$HOME/.local/share/jamovi/modules/StratificationKEN/R"; do
  if [ -d "$lib" ]; then
    export R_LIBS="${R_LIBS:+$R_LIBS:}$lib"
  fi
done
[ -n "${R_LIBS:-}" ] && echo "R_LIBS: $R_LIBS" >&2

if [ "${1:-}" = "--test" ]; then
  exec "$rscript" "$here/tests/run_tests.R"
fi

if [ "$#" -eq 0 ]; then
  exec "$rscript" "$here/bin/stratify.R" --help
fi
exec "$rscript" "$here/bin/stratify.R" "$@"
