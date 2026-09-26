########################################################
# To build the image (run from the repo root; the build context must be the
# repo root because the Dockerfile COPYs the source tree into the image):
#
# docker build -t crabber -f docker/crabber.Dockerfile .
#
# To load the image:
#
# docker run -v `pwd`:/host -it crabber
########################################################

ARG BASE_IMAGE=jammy-llvm14
FROM seahorn/buildpack-deps-seahorn:$BASE_IMAGE

### Download crab
RUN cd / && rm -rf /crab && \
    git clone -b dev https://github.com/seahorn/crab crab;

### Install Lean
#
# Without lake on PATH the build still succeeds -- --verify-with-lean is a
# configure-time option and CMake's else branch simply turns it off -- but every
# lean-* test then lives inside a dead `if (LAKE_EXECUTABLE)` and ctest below
# reports a pass having run none of them. So the toolchain is not optional here:
# it is what makes the Lean verdicts a CI signal rather than local-only.
#
# Only the toolchain pin is copied at this point, ahead of the source tree. elan
# then installs exactly the version lean/lean-toolchain names, and the download
# -- much the largest part of this -- is cached until that pin changes, instead
# of being redone whenever any crabber source file is edited.
ENV ELAN_HOME=/opt/elan
ENV PATH="$ELAN_HOME/bin:$PATH"
COPY lean/lean-toolchain /tmp/lean-toolchain
RUN curl -sSfL https://elan.lean-lang.org/elan-init.sh | \
    sh -s -- -y --no-modify-path --default-toolchain "$(cat /tmp/lean-toolchain)"

## Install crabber from the build context (the checked-out source), so CI
## builds exactly what was checked out -- including PR branches and local
## uncommitted changes -- rather than re-cloning a published ref.
COPY . /crabber
RUN mkdir -p /crabber/build
WORKDIR /crabber/build
RUN cmake -GNinja \
          -DCMAKE_BUILD_TYPE=RelWithDebInfo \
          -DCMAKE_INSTALL_PREFIX=run \
          -DCMAKE_CXX_COMPILER=clang++-14 \
	  -DCRAB_ROOT=/crab \
          -DCRAB_USE_LDD=ON \
          -DLAKE_EXECUTABLE=$ELAN_HOME/bin/lake \
          -DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
          ../ && \
    cmake --build . --target ldd  && cmake .. && \
    cmake --build . --target install
ENV PATH "/crabber/build/run/bin:$PATH"

# Run tests. The sample programs are registered as CTest tests in
# CMakeLists.txt (mirroring the invocations that used to live here); the LDD
# tests are included because Crab is built above with -DCRAB_USE_LDD=ON, and the
# lean-* tests because lake was installed above.
#
# Still skipped: the seven lean-* cases guarded by `if (CRAB_USE_APRON)`,
# including the oct regression test. Enabling Apron means building it, MPFR and
# GMP from source in this image; it is a separate decision from installing Lean.
WORKDIR /crabber/build
RUN ctest --output-on-failure