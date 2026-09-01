# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project overview

Public container image builds of [frp](https://github.com/fatedier/frp),
published to `ghcr.io/coff33cat/frps` and `ghcr.io/coff33cat/frpc` for
`linux/amd64`, `linux/arm64` and `linux/arm/v7`.

The images are deliberately generic: no configuration is baked in and there is
no entrypoint script. `ENTRYPOINT` is the frp binary itself and `CMD` is
`-c /etc/frp/frp{s,c}.toml`, so users mount their own config and can pass any
flag the binary accepts.

## Layout

| Path | Purpose |
|---|---|
| `server/Dockerfile` | frps image |
| `client/Dockerfile` | frpc image |
| `hack/smoke-test.sh` | end-to-end check of an frps/frpc image pair |
| `.github/workflows/build.yml` | version resolution, build, test, publish |
| `examples/` | sample configs and Compose files referenced by the README |

## Build commands

```sh
docker build --build-arg FRP_VERSION=v0.71.0 -t frps:local server/
docker build --build-arg FRP_VERSION=v0.71.0 -t frpc:local client/
FRPS_IMAGE=frps:local FRPC_IMAGE=frpc:local hack/smoke-test.sh
```

`FRP_VERSION` is required; the Dockerfiles pin no frp version anywhere.

## Dockerfile structure

Three stages, and the first two both run on `$BUILDPLATFORM`:

1. **`web`** (node) — clones the frp source at the release tag and builds the
   web UI. It is architecture independent, so BuildKit builds it once and
   shares it across every target platform.
2. **`build`** (golang) — cross-compiles with `GOOS`/`GOARCH`/`GOARM` from
   `TARGETOS`/`TARGETARCH`/`TARGETVARIANT`. frp is pure Go with `CGO_ENABLED=0`,
   so this is a real cross-compile rather than emulation.
3. runtime (alpine) — copies the binary and zoneinfo. **This stage runs no
   command on purpose**, so no QEMU is needed for any target. Adding a `RUN`
   here would force emulation into the build; copy from a builder stage instead.

The web UI is embedded through `//go:embed dist` in the upstream
`web/frps/embed.go`. If `web/frps/dist` is missing, upstream's Makefile would
fall back to a `noweb` build; we build the binary directly with `-tags frps`, so
a missing `dist` is a compile error instead. The smoke test additionally checks
that the dashboard is actually served.

## CI

`build.yml` has two jobs:

- **`resolve`** works out which frp version to build (the newest upstream
  release, or an explicitly requested one) and whether it is already published.
  An explicitly requested version never gets the `latest` tag.
- **`build`** builds each image for the runner's architecture first, runs the
  smoke test against that pair, and only then builds and pushes all three
  architectures. The buildx builder lives for the whole job, so the multi-arch
  build reuses the layers from the test build.

After pushing, the manifests are inspected to confirm every architecture is
present. Attestation manifests (`unknown/unknown`) are filtered out of that
check.

Run `actionlint` after changing the workflow.

## Formatting

Per `.editorconfig`: UTF-8, LF, final newline, 4-space indent, 2 spaces for
YAML, Dockerfiles and TOML.
