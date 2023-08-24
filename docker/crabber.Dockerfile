########################################################
# To build the image:
#
# docker build -t crabber -f crabber.Dockerfile .
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

## Download/install crabber
RUN cd / && rm -rf /crabber && \
    git clone https://github.com/caballa/crabber crabber; \
    mkdir -p /crabber/build
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
WORKDIR /crabber/samples

# Run tests

RUN crabber test-1.crabir  -d int
RUN crabber test-3.crabir  -d int
RUN crabber test-4.crabir  -d oct-snf
#RUN crabber test-5.crabir  -d int --widening-thresholds 10 --print-invariants |  grep -E "^b1: \({}, {n -> \[0, 60\]}\)$"
RUN crabber test-6.crabir  -d int
RUN crabber test-7.crabir  -d boxes --widening-delay 10
RUN crabber test-7.crabir  -d int-set --widening-delay 10
RUN crabber test-7.crabir  -d int-val-part --widening-delay 10
RUN crabber test-7.crabir  -d zones-val-part --widening-delay 10
RUN crabber test-8.crabir -d zones
RUN crabber test-9.crabir -d non-unit-oct --coefficients "4,8"
RUN crabber test-10.crabir -d int-terms