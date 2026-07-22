#!/usr/bin/env bash
#
# Refresh the GitHub Pages folder (docs/) from the current WASM build.
# Run after ./build.sh, then commit + push docs/ to publish.
#
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DOCS="$(cd "$HERE/.." && pwd)/docs"

for f in crabber.js crabber.wasm; do
  [ -f "$HERE/$f" ] || { echo "error: $HERE/$f missing — run ./build.sh first"; exit 1; }
done

# Regenerate the CTest examples list from ../samples.
python3 "$HERE/gen-examples.py"

mkdir -p "$DOCS"
cp "$HERE/index.html" "$HERE/crabber.js" "$HERE/crabber.wasm" "$HERE/examples.js" "$DOCS/"
touch "$DOCS/.nojekyll"
echo ">> updated $DOCS  (index.html, crabber.js, crabber.wasm, examples.js)"
echo ">> commit + push docs/ to publish, e.g.:"
echo "     git add docs && git commit -m 'Update WASM playground' && git push"
