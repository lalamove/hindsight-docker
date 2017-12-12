FROM gcr.io/google-containers/debian-base-amd64:0.3 as builder

# Install build requirements
RUN apt-get update && apt-get dist-upgrade -y
RUN apt-get install -y liblua5.3-dev cmake build-essential git librdkafka-dev libssl1.0-dev zlib1g-dev libsystemd-dev curl libcurl4-openssl-dev ca-certificates libgeoip-dev libsnappy-dev automake

# Build lua_sandbox and install to /app without prefix
WORKDIR /app/src
RUN git clone https://github.com/mozilla-services/lua_sandbox.git
RUN mkdir lua_sandbox/release
WORKDIR lua_sandbox/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_INSTALL_PREFIX='' ..
RUN DESTDIR=/app make install

# Build lua_sandbox_extensions to /app without prefix
WORKDIR /app/src
RUN git clone https://github.com/mozilla-services/lua_sandbox_extensions.git
RUN mkdir lua_sandbox_extensions/release
WORKDIR lua_sandbox_extensions/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_INSTALL_PREFIX='' -DCMAKE_PREFIX_PATH=/app \
        -DEXT_aws=off \
        -DEXT_bloom_filter=on \
        -DEXT_circular_buffer=on \
        -DEXT_cjson=on \
        -DEXT_compat=on \
        -DEXT_cuckoo_filter=on \
        -DEXT_elasticsearch=on \
        -DEXT_geoip=on \
        -DEXT_heka=on \
        -DEXT_hyperloglog=on \
        -DEXT_jose=off \
        -DEXT_kafka=on \
        -DEXT_lfs=on \
        -DEXT_lpeg=on \
        -DEXT_lsb=on \
        -DEXT_moz_ingest=off \
        -DEXT_moz_logging=off \
        -DEXT_moz_pioneer=off \
        -DEXT_moz_security=off \
        -DEXT_moz_telemetry=off \
        -DEXT_openssl=on \
        -DEXT_parquet=off \
        -DEXT_postgres=off \
        -DEXT_rjson=on \
        -DEXT_sax=on \
        -DEXT_snappy=on \
        -DEXT_socket=on \
        -DEXT_ssl=on \
        -DEXT_struct=on \
        -DEXT_syslog=on \
        -DEXT_systemd=on \
        -DEXT_zlib=on \
        ..
RUN CMAKE_PREFIX_PATH=/app CPATH=/app/include DESTDIR=/app make install

# Build hindsight to /app without prefix and link it to lua_sandbox
WORKDIR /app/src
RUN git clone https://github.com/mozilla-services/hindsight.git
WORKDIR /app/src
RUN mkdir hindsight/release
WORKDIR hindsight/release
RUN cmake -DCMAKE_BUILD_TYPE=release -DCMAKE_PREFIX_PATH=/app -DCMAKE_INSTALL_PREFIX='' ..
RUN CMAKE_PREFIX_PATH=/app CPATH=/app/include DESTDIR=/app make install

# Stage /app folder so it can be copied
WORKDIR /app
RUN mkdir -p bin cfg input output/input load run/input run/analysis run/output lib
RUN rm -r src include app

FROM gcr.io/google-containers/debian-base-amd64:0.3

RUN apt-get update && apt-get install -y lua-rex-pcre libssl1.0 ca-certificates librdkafka1 zlib1g libgeoip1 libsnappy1v5 geoip-database geoip-database-extra && rm -r /var/lib/apt/*
COPY --from=builder /app/ /app/
ADD cfg/hindsight.cfg /app/cfg/

RUN useradd -U -d /app hindsight && chown -R hindsight: /app
USER hindsight

VOLUME /app/output /app/load /app/run /app/input
WORKDIR /app/
ENV LD_LIBRARY_PATH /app/lib/
ENTRYPOINT [ "/app/bin/hindsight"]
CMD cfg/hindsight.cfg
