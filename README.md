# frp-container-images

Container images for [frp](https://github.com/fatedier/frp), published to the
GitHub Container Registry.

[![Build images](https://github.com/coff33cat/frp-container-images/actions/workflows/build.yml/badge.svg)](https://github.com/coff33cat/frp-container-images/actions/workflows/build.yml)

| Image | Pull |
|---|---|
| **frps** — the server, runs on a host with a public address | `docker pull ghcr.io/coff33cat/frps:latest` |
| **frpc** — the client, runs next to the services you expose | `docker pull ghcr.io/coff33cat/frpc:latest` |

Available for `linux/amd64`, `linux/arm64` and `linux/arm/v7`, with the frps
dashboard and the frpc admin UI included. No configuration is baked in and
there is no entrypoint script: the container runs the frp binary directly, so
anything you pass to `docker run` goes straight to it.

## Tags

| Tag | Points at |
|---|---|
| `latest` | the newest upstream release |
| `0.71` | the newest patch release of that minor version |
| `0.71.0` | that frp release |

New upstream releases are picked up automatically. All three tags move —
`0.71.0` is republished whenever the base image is refreshed — so pin by digest
if you need a reference that never changes:

```bash
docker pull ghcr.io/coff33cat/frps@sha256:...
```

## Quick start

**On the server:**

```bash
docker run -d --name frps \
  -p 7000:7000 -p 8080:8080 \
  -v "$PWD/frps.toml:/etc/frp/frps.toml:ro" \
  ghcr.io/coff33cat/frps:latest
```

**Next to the service you want to reach:**

```bash
docker run -d --name frpc \
  -v "$PWD/frpc.toml:/etc/frp/frpc.toml:ro" \
  ghcr.io/coff33cat/frpc:latest
```

Ready-made starting points are in [`examples/`](examples): `frps.toml`,
`frpc.toml` and a Compose file for each side.

## Configuration

The images carry no configuration of their own. Mount yours at:

- `/etc/frp/frps.toml` for frps
- `/etc/frp/frpc.toml` for frpc

That path is only the default argument, so you can put the file anywhere and
point at it instead:

```bash
docker run -v "$PWD/conf:/conf:ro" ghcr.io/coff33cat/frps:latest -c /conf/my-frps.toml
```

Mounting a directory rather than a single file works well together with frp's
own `includes` option, which lets you keep one proxy per file:

```toml
includes = ["/etc/frp/conf.d/*.toml"]
```

frp's `verify` subcommand is a quick way to check a config before deploying it:

```bash
docker run --rm -v "$PWD/frps.toml:/etc/frp/frps.toml:ro" \
  ghcr.io/coff33cat/frps:latest verify -c /etc/frp/frps.toml
```

For the full set of options, see the upstream reference for
[frps](https://github.com/fatedier/frp/blob/dev/conf/frps.full_example.toml) and
[frpc](https://github.com/fatedier/frp/blob/dev/conf/frpc.full_example.toml).

## Ports

Nothing is `EXPOSE`d, because which ports matter depends entirely on your
config. The ones you will usually want to publish on the frps side:

| Config option | Typical port | Purpose |
|---|---|---|
| `bindPort` | 7000 | where frpc connects |
| `vhostHTTPPort` | 8080 | HTTP proxies (`type = "http"`) |
| `vhostHTTPSPort` | 8443 | HTTPS proxies |
| `webServer.port` | 7500 | dashboard — keep it off public interfaces |
| `remotePort` per proxy | — | one per TCP/UDP proxy you define |

frpc normally needs no published ports at all; it dials out.

## Running as a non-root user

The binary does not need root unless it binds a port below 1024 inside the
container, so this is usually all it takes:

```yaml
services:
  frps:
    image: ghcr.io/coff33cat/frps:latest
    user: "65534:65534"
```

## License

The packaging in this repository is licensed under the
[Apache License 2.0](LICENSE). frp itself is a separate project, also under
Apache 2.0 — see [fatedier/frp](https://github.com/fatedier/frp).
