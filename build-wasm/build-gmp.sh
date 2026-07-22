#!/usr/bin/env bash
#
# One-time: cross-compile GMP to WebAssembly for the crabber WASM build.
# Produces  $PREFIX/lib/libgmp.a  and  $PREFIX/include/gmp.h
# (default PREFIX = build-wasm/gmp-wasm).
#
# Requires an active Emscripten SDK:  source <emsdk>/emsdk_env.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${WASM_PREFIX:-$HERE/gmp-wasm}"
GMP_VER="${GMP_VER:-6.3.0}"
WORK="$HERE/.gmp-build"

command -v emcc >/dev/null || { echo "error: emcc not found. Run: source <emsdk>/emsdk_env.sh"; exit 1; }

if [ -f "$PREFIX/lib/libgmp.a" ] && [ -f "$PREFIX/include/gmp.h" ]; then
  echo "GMP already built at $PREFIX — nothing to do."
  exit 0
fi

mkdir -p "$WORK"; cd "$WORK"
if [ ! -d "gmp-$GMP_VER" ]; then
  echo ">> downloading GMP $GMP_VER"
  curl -fsSL -o "gmp-$GMP_VER.tar.xz" "https://gmplib.org/download/gmp/gmp-$GMP_VER.tar.xz"
  tar xf "gmp-$GMP_VER.tar.xz"
fi
cd "gmp-$GMP_VER"

echo ">> configuring GMP for wasm32"
# --host=none: GMP has no wasm host triplet; disables asm and uses generic C.
# CC_FOR_BUILD: GMP needs a NATIVE compiler for its build-time codegen tools;
#   without this it wrongly picks Emscripten's clang and configure fails.
# No --enable-cxx: Crab uses GMP's C API only (mpz_t), never gmpxx.
emconfigure ./configure \
  --host=none --disable-assembly --disable-shared --enable-static \
  CC_FOR_BUILD="${CC_FOR_BUILD:-/usr/bin/cc}" \
  --prefix="$PREFIX"

echo ">> building + installing GMP"
emmake make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc || echo 4)"
emmake make install

echo ">> done: $PREFIX/lib/libgmp.a"
