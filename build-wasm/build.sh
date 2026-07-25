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
#   MPFR_WASM_PREFIX / APRON_WASM_PREFIX        (defaults: build-wasm/{mpfr,apron}-wasm)
#
# Apron IS cross-compiled to wasm (build-mpfr.sh + build-apron.sh), so this build
# enables HAVE_APRON via wasm-config/crab/config.h. That turns on the Apron-backed
# domains: pk (polyhedra) and oct; non-unit-oct is also routed through Apron oct,
# matching a native -DCRAB_USE_APRON=ON build.
#
# Still excluded vs. the native build (need other external C libraries):
#   boxes (LDD), pk-pplite (PPLite), elina.
# Only boxes_domain.cpp is skipped. Working domains:
#   int, dis-int, int-terms, int-set, int-val-part,
#   zones, zones-val-part, oct-snf, non-unit-oct, oct, pk.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CRABBER="$(cd "$HERE/.." && pwd)"
# Default CRAB_ROOT: prefer an in-repo checkout (crabber/crab), else the sibling ../crab.
if [ -z "${CRAB_ROOT:-}" ]; then
  if [ -d "$CRABBER/crab/include/crab" ]; then CRAB_ROOT="$CRABBER/crab"
  else CRAB_ROOT="$(cd "$CRABBER/.." && pwd)/crab"; fi
fi
BOOST_INC="${BOOST_INC:-/opt/homebrew/include}"
WASM_PREFIX="${WASM_PREFIX:-$HERE/gmp-wasm}"
MPFR_PREFIX="${MPFR_WASM_PREFIX:-$HERE/mpfr-wasm}"
APRON_PREFIX="${APRON_WASM_PREFIX:-$HERE/apron-wasm}"

command -v emcc >/dev/null || { echo "error: emcc not found. Run: source <emsdk>/emsdk_env.sh"; exit 1; }
[ -d "$CRAB_ROOT/include/crab" ] || { echo "error: crab source not found at CRAB_ROOT=$CRAB_ROOT"; exit 1; }
[ -d "$BOOST_INC/boost" ]        || { echo "error: boost headers not found at BOOST_INC=$BOOST_INC"; exit 1; }

# Ensure the wasm GMP exists (builds it once).
if [ ! -f "$WASM_PREFIX/lib/libgmp.a" ]; then
  echo ">> GMP wasm build not found; running build-gmp.sh"
  WASM_PREFIX="$WASM_PREFIX" "$HERE/build-gmp.sh"
fi
# Ensure the wasm MPFR + Apron exist (built once; needed by the pk / oct domains).
if [ ! -f "$MPFR_PREFIX/lib/libmpfr.a" ]; then
  echo ">> MPFR wasm build not found; running build-mpfr.sh"
  WASM_PREFIX="$WASM_PREFIX" MPFR_WASM_PREFIX="$MPFR_PREFIX" "$HERE/build-mpfr.sh"
fi
if [ ! -f "$APRON_PREFIX/lib/libpolkaMPQ.a" ]; then
  echo ">> Apron wasm build not found; running build-apron.sh"
  WASM_PREFIX="$WASM_PREFIX" MPFR_WASM_PREFIX="$MPFR_PREFIX" APRON_WASM_PREFIX="$APRON_PREFIX" "$HERE/build-apron.sh"
fi

OBJ="$HERE/obj"; rm -rf "$OBJ"; mkdir -p "$OBJ/crab" "$OBJ/crabber" "$HERE/lib"

FLAGS="-std=c++14 -O2 -DNDEBUG"   # -DNDEBUG matches native Release: strips Crab's internal assert()s
# wasm-config MUST be first so its crab/config.h (all optional backends off)
# shadows any backend-enabled config.h. No native crab install is required.
INC="-I$HERE/wasm-config -I$CRABBER/include -I$CRABBER/external \
     -I$CRAB_ROOT/include -I$BOOST_INC -I$WASM_PREFIX/include \
     -I$MPFR_PREFIX/include -I$APRON_PREFIX/include"

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
# Apron domain libs (pk=polkaMPQ, oct=octMPQ) before libapron; then mpfr, gmp.
# We use octMPQ (exact rationals), NOT octD (doubles): octD needs outward FPU
# rounding via fesetround(), which wasm does not support, so octD would be
# UNSOUND here. octD is deliberately not linked — it defines the same
# oct_manager_alloc as octMPQ and would clash.
em++ -O2 "$OBJ"/crabber/*.o "$HERE/lib/libcrab_wasm.a" \
  "$APRON_PREFIX/lib/libpolkaMPQ.a" "$APRON_PREFIX/lib/liboctMPQ.a" \
  "$APRON_PREFIX/lib/libapron.a" "$MPFR_PREFIX/lib/libmpfr.a" "$WASM_PREFIX/lib/libgmp.a" \
  -o "$HERE/crabber.js" \
  -s MODULARIZE=1 -s EXPORT_NAME=Crabber \
  -s INVOKE_RUN=0 -s EXIT_RUNTIME=0 \
  -s FORCE_FILESYSTEM=1 -s ALLOW_MEMORY_GROWTH=1 \
  -s "EXPORTED_RUNTIME_METHODS=['callMain','FS']"

rm -rf "$OBJ"
echo ">> done: $HERE/crabber.wasm  +  $HERE/crabber.js"
