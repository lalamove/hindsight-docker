FROM gcr.io/google-containers/debian-base-amd64:0.3.2 as builder
ENV HINDSIGHT_VERSION 81cef011138f36e8a3e6ff77ec409786840a3055
ENV SANDBOX_VERSION 513940503aafc937d19868bb5e889bb0020cd26b

# Install build requirements
RUN apt-get update && apt-get dist-upgrade -y
RUN apt-get install -y liblua5.3-dev cmake build-essential git librdkafka-dev libssl1.0-dev zlib1g-dev libsystemd-dev curl libcurl4-openssl-dev ca-certificates libmaxminddb-dev libsnappy-dev automake wget libboost-regex-dev libboost-filesystem-dev libboost-system-dev libboost-dev libboost-program-options-dev libboost-test-dev libtool bison flex pkg-config libjansson-dev

# Build lua_sandbox and install to /hindsight without prefix
WORKDIR /hindsight/src
RUN git clone https://github.com/mozilla-services/lua_sandbox.git
RUN git --git-dir lua_sandbox/.git reset --hard $SANDBOX_VERSION 
RUN mkdir lua_sandbox/release
WORKDIR lua_sandbox/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_INSTALL_PREFIX='' ..
RUN DESTDIR=/hindsight make install

# Install cjose
WORKDIR /hindsight/src
RUN git clone --depth 1 --branch 0.5.1 https://github.com/cisco/cjose.git
WORKDIR cjose
RUN ./configure --prefix=/hindsight
RUN make install

# Install parquet
WORKDIR /hindsight/src
RUN git clone --depth 1 --branch apache-arrow-0.7.1 -- https://github.com/apache/arrow.git
RUN mkdir -p arrow/cpp/release
WORKDIR arrow/cpp/release
RUN cmake -DCMAKE_BUILD_TYPE=Release -DARROW_BUILD_TESTS=Off .. -DCMAKE_INSTALL_PREFIX='/hindsight'
RUN make install
WORKDIR /hindsight/src
RUN git clone --depth 1 --branch apache-parquet-cpp-1.3.1 -- https://github.com/apache/parquet-cpp.git
RUN mkdir -p parquet-cpp/release
WORKDIR parquet-cpp/release
RUN cmake -DCMAKE_BUILD_TYPE=Release -DPARQUET_MINIMAL_DEPENDENCY=ON -DPARQUET_BUILD_TESTS=Off -DPARQUET_BUILD_BENCHMARKS=Off -DPARQUET_BUILD_EXECUTABLES=Off .. -DCMAKE_PREFIX_PATH=/hindsight -DCMAKE_INSTALL_PREFIX='/hindsight'
RUN make install
## BUG FIX
RUN sed -i 's/PRIMITIVE_FACTORY(\(.\+\));/PRIMITIVE_FACTORY(\1)/' /hindsight/include/parquet/schema.h

# Build lua_sandbox_extensions to /hindsight without prefix
# Install all extensions as latest versions (from master)
WORKDIR /hindsight/src
RUN git clone --depth 1 --branch master https://github.com/mozilla-services/lua_sandbox_extensions.git
RUN mkdir lua_sandbox_extensions/release
WORKDIR lua_sandbox_extensions/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_SHARED_LINKER_FLAGS="-L/hindsight/lib" -DCMAKE_INSTALL_PREFIX='' -DCMAKE_PREFIX_PATH=/hindsight \
        -DENABLE_ALL_EXT=true \
        -DEXT_aws=off \
        -DEXT_gcp=off \
        -DEXT_moz_ingest=off \
        -DEXT_moz_logging=off \
        -DEXT_moz_pioneer=off \
        -DEXT_moz_security=off \
        -DEXT_moz_telemetry=off \
        -DEXT_postgres=off \
        ..
RUN luasandbox_DIR=/hindsight/share/luasandbox/cmake CPATH=/hindsight/include make
RUN DESTDIR=/hindsight make install
RUN rsync -av /hindsight/hindsight/src/lua_sandbox_extensions/release/install/ /hindsight/

# Build and install lua_date extension to /hindsight
WORKDIR /hindsight/src
RUN git clone --depth 1 --recursive https://github.com/trink/lua_date.git
WORKDIR lua_date
RUN git submodule update --init
RUN mkdir release
WORKDIR release
RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='' -Dluasandbox_DIR=/hindsight/share/luasandbox/cmake ..
RUN DESTDIR=/hindsight make install

# Build and install streaming_algorithms extension to /hindsight
WORKDIR /hindsight/src
RUN git clone --depth 1 --recursive https://github.com/trink/streaming_algorithms.git
WORKDIR streaming_algorithms
RUN mkdir release
WORKDIR release
RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX='' -Dluasandbox_DIR=/hindsight/share/luasandbox/cmake ..
RUN DESTDIR=/hindsight make install

# Build hindsight to /hindsight without prefix and link it to lua_sandbox
WORKDIR /hindsight/src
RUN git clone https://github.com/mozilla-services/hindsight.git
RUN git --git-dir hindsight/.git reset --hard $HINDSIGHT_VERSION 
RUN mkdir hindsight/release
WORKDIR hindsight/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_PREFIX_PATH=/hindsight -DCMAKE_INSTALL_PREFIX='' ..
RUN CMAKE_PREFIX_PATH=/hindsight CPATH=/hindsight/include DESTDIR=/hindsight make install

# Stage /hindsight folder so it can be copied
WORKDIR /hindsight
RUN mkdir -p bin cfg var
RUN rm -r src include hindsight
WORKDIR /hindsight/var
RUN mkdir -p output load/input load/analysis load/output
RUN cp -r load run

# Build actual hindsight container!
FROM gcr.io/google-containers/debian-base-amd64:0.3.2

RUN sed -i 's/main/main contrib/g' /etc/apt/sources.list && apt-get update && \
    apt-get --no-install-recommends install -y \
        lua-rex-pcre \
        libssl1.0 \
        ca-certificates \
        librdkafka1 \
        zlib1g \
        libmaxminddb0 \
        libsnappy1v5 \
        geoipupdate \
        libboost-regex1.62.0 \
        libboost-system1.62.0 \
        libboost-filesystem1.62.0 \
    && \
    rm -r /var/lib/apt/*
COPY --from=builder /hindsight/ /hindsight
ADD cfg/hindsight.cfg /hindsight/cfg
ADD entrypoint.sh /entrypoint.sh
ADD input/prune_input.cfg /hindsight/var/run/input
ADD GeoIP.conf /etc/GeoIP.conf

RUN geoipupdate -v

RUN useradd -U -d /hindsight/var hindsight && chown -R hindsight: /hindsight/var

VOLUME /hindsight/var
WORKDIR /hindsight/var
ENV LD_LIBRARY_PATH /hindsight/lib
ENV IANA_TZDATA /hindsight/share/iana/tzdata
ENTRYPOINT [ "/entrypoint.sh"]
CMD ["/hindsight/bin/hindsight", "/hindsight/cfg/hindsight.cfg"]
