# syntax=docker/dockerfile:1

# frpc -- the frp client, built from the upstream source tree.
#
#   docker build --build-arg FRP_VERSION=v0.71.0 -t frpc:local client/

ARG NODE_VERSION=24
ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3
ARG FRP_VERSION

# The admin UI is architecture independent, so it is built once on the build
# platform and shared by every target architecture.
FROM --platform=$BUILDPLATFORM node:${NODE_VERSION} AS web
ARG FRP_VERSION
WORKDIR /source
RUN test -n "${FRP_VERSION}" || { echo "FRP_VERSION build arg is required (e.g. v0.71.0)" >&2; exit 1; }; \
  git clone --depth 1 --branch "${FRP_VERSION}" https://github.com/fatedier/frp.git .
WORKDIR /source/web
RUN npm ci && npm run build --workspace frpc

# frp is pure Go with cgo disabled, so cross-compiling from the build platform
# is both correct and far faster than emulating the target architecture.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
COPY --from=web /source /source
WORKDIR /source
RUN --mount=type=cache,target=/go/pkg/mod \
  --mount=type=cache,target=/root/.cache/go-build \
  GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" GOARM="${TARGETVARIANT#v}" CGO_ENABLED=0 \
  go build -trimpath -ldflags "-s -w" -tags frpc -o /out/frpc ./cmd/frpc

FROM alpine:${ALPINE_VERSION}
ARG FRP_VERSION
# zoneinfo is copied rather than installed with apk so that this stage runs no
# command at all and therefore needs no emulation. Alpine already ships the CA
# bundle, which is the only other thing frpc needs from the base image.
COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /out/frpc /usr/bin/frpc

LABEL org.opencontainers.image.title="frpc" \
  org.opencontainers.image.description="frp client (frpc), built from source" \
  org.opencontainers.image.version="${FRP_VERSION}" \
  org.opencontainers.image.licenses="Apache-2.0"

# No configuration is baked into the image: mount your own frpc.toml.
ENTRYPOINT ["/usr/bin/frpc"]
CMD ["-c", "/etc/frp/frpc.toml"]
