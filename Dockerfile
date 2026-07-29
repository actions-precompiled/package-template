# Build environment for relocatable package binaries.
# Native multi-arch: build on amd64 or arm64 runners (no QEMU cross).
#
# Edit the apt packages for your project's compile-time dependencies.
FROM ubuntu:24.04

ARG TARGETARCH=

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        ninja-build \
        pkg-config \
        patchelf \
        file \
        tar \
        xz-utils \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY scripts/build_and_package.sh /usr/local/bin/build_and_package.sh
RUN chmod +x /usr/local/bin/build_and_package.sh

ENTRYPOINT ["/usr/local/bin/build_and_package.sh"]
