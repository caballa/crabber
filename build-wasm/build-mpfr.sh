#!/usr/bin/env bash
#
# One-time: cross-compile MPFR to WebAssembly for the crabber WASM build.
# MPFR is a dependency of Apron (needed by the pk / polyhedra domain).
# Produces  $PREFIX/lib/libmpfr.a  and  $PREFIX/include/mpfr.h
# (default PREFIX = build-wasm/mpfr-wasm). Needs the wasm GMP built first.
#
# Requires an active Emscripten SDK:  source <emsdk>/emsdk_env.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${MPFR_WASM_PREFIX:-$HERE/mpfr-wasm}"
GMP_PREFIX="${WASM_PREFIX:-$HERE/gmp-wasm}"
MPFR_VER="${MPFR_VER:-4.2.1}"
WORK="$HERE/.mpfr-build"

command -v emcc >/dev/null || { echo "error: emcc not found. Run: source <emsdk>/emsdk_env.sh"; exit 1; }
[ -f "$GMP_PREFIX/lib/libgmp.a" ] || { echo "error: wasm GMP not found at $GMP_PREFIX; run build-gmp.sh first"; exit 1; }

if [ -f "$PREFIX/lib/libmpfr.a" ] && [ -f "$PREFIX/include/mpfr.h" ]; then
  echo "MPFR already built at $PREFIX — nothing to do."
  exit 0
fi

mkdir -p "$WORK"; cd "$WORK"
if [ ! -d "mpfr-$MPFR_VER" ]; then
  echo ">> downloading MPFR $MPFR_VER"
  curl -fsSL -o "mpfr-$MPFR_VER.tar.xz" "https://www.mpfr.org/mpfr-$MPFR_VER/mpfr-$MPFR_VER.tar.xz"
  tar xf "mpfr-$MPFR_VER.tar.xz"
fi
cd "mpfr-$MPFR_VER"

echo ">> configuring MPFR for wasm32"
# --host=wasm32-unknown-emscripten: cross-compile mode (configure won't try to
#   run test binaries). --with-gmp points at the wasm GMP built by build-gmp.sh.
emconfigure ./configure \
  --host=wasm32-unknown-emscripten \
  --disable-shared --enable-static \
  --with-gmp="$GMP_PREFIX" \
  --prefix="$PREFIX"

echo ">> building + installing MPFR"
emmake make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc || echo 4)"
emmake make install

echo ">> done: $PREFIX/lib/libmpfr.a"
