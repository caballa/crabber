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
          -DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
          ../ && \
    cmake --build . --target ldd  && cmake .. && \
    cmake --build . --target install
ENV PATH "/crabber/build/run/bin:$PATH"

# Run tests. The sample programs are registered as CTest tests in
# CMakeLists.txt (mirroring the invocations that used to live here); the LDD
# tests are included because Crab is built above with -DCRAB_USE_LDD=ON.
WORKDIR /crabber/build
RUN ctest --output-on-failure