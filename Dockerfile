ARG BASE_VARIANT=alpine
ARG GO_VERSION=1.17
ARG XX_VERSION=1.1.0

ARG LIBGIT2_IMG
ARG LIBGIT2_TAG

FROM ${LIBGIT2_IMG}:${LIBGIT2_TAG} as build

# Configure workspace
WORKDIR /workspace

# Copy api submodule
COPY api/ api/

# Copy modules manifests
COPY go.mod go.mod
COPY go.sum go.sum

# Cache modules
RUN go mod download

RUN apk add clang lld pkgconfig ca-certificates

ENV CGO_ENABLED=1
ARG TARGETPLATFORM

RUN xx-apk add --no-cache \
        musl-dev gcc lld binutils-gold

# Performance related changes:
# - Use read-only bind instead of copying go source files.
# - Cache go packages.
RUN --mount=target=. \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    export LIBRARY_PATH="/usr/local/$(xx-info triple)/lib:/usr/local/$(xx-info triple)/lib64:${LIBRARY_PATH}" && \
    export PKG_CONFIG_PATH="/usr/local/$(xx-info triple)/lib/pkgconfig:/usr/local/$(xx-info triple)/lib64/pkgconfig" && \
	export FLAGS="$(pkg-config --static --libs --cflags libssh2 openssl libgit2)" && \
	xx-go build \
        -ldflags "-s -w -extldflags \"/usr/lib/$(xx-info triple)/libssh2.a /usr/lib/$(xx-info triple)/libssl.a /usr/lib/$(xx-info triple)/libcrypto.a /usr/lib/$(xx-info triple)/libz.a -Wl,--unresolved-symbols=ignore-in-object-files -Wl,-allow-shlib-undefined ${FLAGS} -static\"" \
        -tags 'netgo,osusergo,static_build' \
        -o /image-automation-controller -trimpath \
    main.go

# Ensure that the binary was cross-compiled correctly to the target platform.
RUN xx-verify --static /image-automation-controller


FROM gcr.io/distroless/static

# Link repo to the GitHub Container Registry image
LABEL org.opencontainers.image.source="https://github.com/fluxcd/image-automation-controller"

# Copy over binary from build
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /image-automation-controller /usr/local/bin/

USER 65534:65534
ENTRYPOINT [ "image-automation-controller" ]