#!/usr/bin/env bash
#
# Build crabber.wasm — a WebAssembly build of crabber that runs in the browser
# or Node with NO server. Produces crabber.js + crabber.wasm in this directory.
#
# Prerequisites:
#   1. Emscripten SDK active:      source <emsdk>/emsdk_env.sh
#   2. Boost headers available     (override with BOOST_INC=..., default Homebrew)
#   3. GMP cross-compiled to wasm  (this script runs ./build-gmp.sh for you)
#
# Path overrides (env vars, all optional):
#   CRAB_ROOT   path to the crab source tree   (default: ../crab relative to repo)
#   BOOST_INC   dir containing <boost/...>      (default: /opt/homebrew/include)
#   WASM_PREFIX GMP wasm install prefix         (default: build-wasm/gmp-wasm)
#
# Excluded vs. the native build (all need external C libraries):
#   boxes (LDD), oct / pk (Apron/Elina), pk-pplite (PPLite).
# Only boxes_domain.cpp is skipped; the apron/pplite domain files are internally
# #ifdef-guarded and compile to no-ops. All pure-C++ domains work:
#   int, dis-int, int-terms, int-set, int-val-part,
#   zones, zones-val-part, oct-snf, non-unit-oct.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CRABBER="$(cd "$HERE/.." && pwd)"
CRAB_ROOT="${CRAB_ROOT:-$(cd "$CRABBER/.." && pwd)/crab}"
BOOST_INC="${BOOST_INC:-/opt/homebrew/include}"
WASM_PREFIX="${WASM_PREFIX:-$HERE/gmp-wasm}"

command -v emcc >/dev/null || { echo "error: emcc not found. Run: source <emsdk>/emsdk_env.sh"; exit 1; }
[ -d "$CRAB_ROOT/include/crab" ] || { echo "error: crab source not found at CRAB_ROOT=$CRAB_ROOT"; exit 1; }
[ -d "$BOOST_INC/boost" ]        || { echo "error: boost headers not found at BOOST_INC=$BOOST_INC"; exit 1; }

# Ensure the wasm GMP exists (builds it once).
if [ ! -f "$WASM_PREFIX/lib/libgmp.a" ]; then
  echo ">> GMP wasm build not found; running build-gmp.sh"
  WASM_PREFIX="$WASM_PREFIX" "$HERE/build-gmp.sh"
fi

OBJ="$HERE/obj"; rm -rf "$OBJ"; mkdir -p "$OBJ/crab" "$OBJ/crabber" "$HERE/lib"

FLAGS="-std=c++14 -O2 -DNDEBUG"   # -DNDEBUG matches native Release: strips Crab's internal assert()s
# wasm-config MUST be first so its crab/config.h (all optional backends off)
# shadows any backend-enabled config.h. No native crab install is required.
INC="-I$HERE/wasm-config -I$CRABBER/include -I$CRABBER/external \
     -I$CRAB_ROOT/include -I$BOOST_INC -I$WASM_PREFIX/include"

echo ">> compiling Crab runtime library"
for f in "$CRAB_ROOT"/lib/*.cpp; do
  em++ $FLAGS $INC -c "$f" -o "$OBJ/crab/$(basename "${f%.cpp}").o"
done
emar rcs "$HERE/lib/libcrab_wasm.a" "$OBJ"/crab/*.o

echo ">> compiling crabber (skipping boxes_domain.cpp)"
srcs=("$CRABBER"/src/crabber.cpp "$CRABBER"/src/parser.cpp \
      "$CRABBER"/src/crabir_builder.cpp "$CRABBER"/src/analyzer.cpp)
for f in "$CRABBER"/src/domains/*.cpp; do
  [ "$(basename "$f")" = boxes_domain.cpp ] && continue
  srcs+=("$f")
done
for f in "${srcs[@]}"; do
  em++ $FLAGS $INC -c "$f" -o "$OBJ/crabber/$(basename "${f%.cpp}").o"
done

echo ">> linking crabber.js + crabber.wasm"
em++ -O2 "$OBJ"/crabber/*.o "$HERE/lib/libcrab_wasm.a" "$WASM_PREFIX/lib/libgmp.a" \
  -o "$HERE/crabber.js" \
  -s MODULARIZE=1 -s EXPORT_NAME=Crabber \
  -s INVOKE_RUN=0 -s EXIT_RUNTIME=0 \
  -s FORCE_FILESYSTEM=1 -s ALLOW_MEMORY_GROWTH=1 \
  -s "EXPORTED_RUNTIME_METHODS=['callMain','FS']"

rm -rf "$OBJ"
echo ">> done: $HERE/crabber.wasm  +  $HERE/crabber.js"
