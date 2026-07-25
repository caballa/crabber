#!/usr/bin/env bash
#
# One-time: cross-compile Apron (the C numerical abstract domain library) to
# WebAssembly so the crabber WASM build can offer the `pk` (polyhedra) domain.
# Produces static archives + headers under $PREFIX (default build-wasm/apron-wasm):
#   $PREFIX/lib/libapron.a  libpolkaMPQ.a  (plus box/oct/... we don't link)
#   $PREFIX/include/ap_global0.h  pk.h  ...
#
# Depends on the wasm GMP (build-gmp.sh) and wasm MPFR (build-mpfr.sh).
# Requires an active Emscripten SDK:  source <emsdk>/emsdk_env.sh
#
# Apron's hand-written ./configure runs compile+link probes; emcc's `-o x.out`
# emits an executable-flagged node script, so `test -x` passes and detection
# works. Two things must be forced, though:
#   * HAS_SHARED= — never build .so/.dylib (emscripten side-modules; we want .a).
#   * AR=emar RANLIB=emranlib — Apron's configure bakes in the native `ar`, which
#     writes an EMPTY symbol table for wasm objects (Apple ar gotcha); emar fixes it.
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${APRON_WASM_PREFIX:-$HERE/apron-wasm}"
GMP_PREFIX="${WASM_PREFIX:-$HERE/gmp-wasm}"
MPFR_PREFIX="${MPFR_WASM_PREFIX:-$HERE/mpfr-wasm}"
APRON_TAG="${APRON_TAG:-e03832465bdca1888c56ecbe14dcdac0a243dce2}"   # matches crab/cmake/download_apron.cmake
WORK="$HERE/.apron-build"

command -v emcc  >/dev/null || { echo "error: emcc not found. Run: source <emsdk>/emsdk_env.sh"; exit 1; }
command -v emar  >/dev/null || { echo "error: emar not found (emsdk not active?)"; exit 1; }
[ -f "$GMP_PREFIX/lib/libgmp.a" ]   || { echo "error: wasm GMP not found at $GMP_PREFIX; run build-gmp.sh";   exit 1; }
[ -f "$MPFR_PREFIX/lib/libmpfr.a" ] || { echo "error: wasm MPFR not found at $MPFR_PREFIX; run build-mpfr.sh"; exit 1; }

if [ -f "$PREFIX/lib/libpolkaMPQ.a" ] && [ -f "$PREFIX/lib/libapron.a" ]; then
  echo "Apron already built at $PREFIX — nothing to do."
  exit 0
fi

mkdir -p "$WORK"; cd "$WORK"
if [ ! -d apron ]; then
  echo ">> cloning Apron"
  git clone --quiet https://github.com/antoinemine/apron.git apron
fi
cd apron
git fetch --quiet --depth 1 origin "$APRON_TAG"
git checkout --quiet "$APRON_TAG"
git clean -fdxq   # drop any prior half-configured state

echo ">> configuring Apron for wasm32 (C libs only)"
# -no-cxx also disables ppl/pplite; -no-glpk/-no-java/-no-ocaml skip those probes.
emconfigure ./configure \
  -prefix "$PREFIX" \
  -no-cxx -no-ppl -no-pplite -no-glpk -no-java -no-ocaml \
  -gmp-prefix "$GMP_PREFIX" \
  -mpfr-prefix "$MPFR_PREFIX"

# Force wasm-correct archiver + static-only, and add release optimization.
MK_VARS=(HAS_SHARED= CC=emcc AR=emar RANLIB=emranlib CPPFLAGS="-O2 -DNDEBUG")

echo ">> building Apron C libraries"
emmake make c "${MK_VARS[@]}"

echo ">> installing Apron to $PREFIX"
emmake make install "${MK_VARS[@]}"

echo ">> done: $PREFIX/lib/libpolkaMPQ.a"
