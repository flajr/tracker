# Containerfile
FROM alpine:latest AS builder

RUN apk add --no-cache build-base git musl-dev pkgconfig

# Install Janet
RUN git clone --depth 1 https://github.com/janet-lang/janet /tmp/janet && \
    cd /tmp/janet && \
    make -j$(nproc) && \
    make install

# Install jpm
RUN git clone --depth 1 https://github.com/janet-lang/jpm /tmp/jpm && \
    cd /tmp/jpm && \
    janet bootstrap.janet

WORKDIR /app
COPY *.janet .
COPY deps ./deps
RUN mkdir -p /output && \
    JANET_PATH=/usr/local/lib/janet \
    CFLAGS="-static -Os -fomit-frame-pointer" \
    LDFLAGS="-static" \
    jpm build && \
    strip -s build/tracker && \
    cp build/tracker /output/tracker-static
