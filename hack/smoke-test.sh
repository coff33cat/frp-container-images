#!/usr/bin/env bash
#
# End-to-end check of a locally available frps/frpc image pair.
#
# Starts frps, a tiny HTTP backend and frpc on a throwaway docker network, then
# verifies that traffic actually reaches the backend through the tunnel and that
# the web UIs built into the images are served.
#
#   FRPS_IMAGE=frps:local FRPC_IMAGE=frpc:local hack/smoke-test.sh

set -euo pipefail

FRPS_IMAGE="${FRPS_IMAGE:-frps:local}"
FRPC_IMAGE="${FRPC_IMAGE:-frpc:local}"
HELPER_IMAGE="${HELPER_IMAGE:-alpine:3}"
BACKEND_IMAGE="${BACKEND_IMAGE:-nginx:alpine}"

SUFFIX="$$"
NETWORK="frp-smoke-${SUFFIX}"
BACKEND="frp-smoke-backend-${SUFFIX}"
SERVER="frp-smoke-frps-${SUFFIX}"
CLIENT="frp-smoke-frpc-${SUFFIX}"
WORKDIR="$(mktemp -d)"
TOKEN="smoke-test-token"
# base64 of admin:admin, for the basic-auth protected web UIs.
AUTH_HEADER="Authorization: Basic YWRtaW46YWRtaW4="

cleanup() {
    local status=$?
    if [ "$status" -ne 0 ]; then
        echo "--- frps log ---" >&2
        docker logs "$SERVER" 2>&1 | tail -n 40 >&2 || true
        echo "--- frpc log ---" >&2
        docker logs "$CLIENT" 2>&1 | tail -n 40 >&2 || true
    fi
    docker rm -f "$BACKEND" "$SERVER" "$CLIENT" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Fetch a URL from inside the test network. Extra args are passed to wget.
fetch() {
    docker run --rm --network "$NETWORK" "$HELPER_IMAGE" \
        wget -q -O - -T 5 "$@"
}

# Retry a command until it succeeds, to absorb container start-up time.
await() {
    local description="$1"
    shift
    local remaining=30
    while [ "${remaining}" -gt 0 ]; do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        remaining=$((remaining - 1))
        sleep 1
    done
    echo "timed out waiting for ${description}" >&2
    return 1
}

# Assert that a URL responds with a body containing the expected substring.
expect_body() {
    local description="$1" expected="$2"
    shift 2
    local body
    body="$(fetch "$@")"
    if [[ "$body" != *"$expected"* ]]; then
        echo "${description}: expected body to contain '${expected}', got:" >&2
        echo "$body" >&2
        return 1
    fi
    echo "ok: ${description}"
}

cat >"$WORKDIR/frps.toml" <<EOF
bindPort = 7000
vhostHTTPPort = 8080

webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"

auth.method = "token"
auth.token = "${TOKEN}"
EOF

cat >"$WORKDIR/frpc.toml" <<EOF
serverAddr = "frps"
serverPort = 7000

auth.method = "token"
auth.token = "${TOKEN}"

webServer.addr = "0.0.0.0"
webServer.port = 7400
webServer.user = "admin"
webServer.password = "admin"

[[proxies]]
name = "smoke-tcp"
type = "tcp"
localIP = "backend"
localPort = 80
remotePort = 6000

[[proxies]]
name = "smoke-http"
type = "http"
localIP = "backend"
localPort = 80
customDomains = ["smoke.example.com"]
EOF

echo "==> ${FRPS_IMAGE} reports version $(docker run --rm "$FRPS_IMAGE" --version)"
echo "==> ${FRPC_IMAGE} reports version $(docker run --rm "$FRPC_IMAGE" --version)"

docker network create "$NETWORK" >/dev/null

echo frp-smoke-ok >"$WORKDIR/index.html"
docker run -d --name "$BACKEND" --network "$NETWORK" --network-alias backend \
    -v "$WORKDIR/index.html:/usr/share/nginx/html/index.html:ro" \
    "$BACKEND_IMAGE" >/dev/null

docker run -d --name "$SERVER" --network "$NETWORK" --network-alias frps \
    -v "$WORKDIR/frps.toml:/etc/frp/frps.toml:ro" "$FRPS_IMAGE" >/dev/null

await "frps dashboard" fetch --header "$AUTH_HEADER" http://frps:7500/

docker run -d --name "$CLIENT" --network "$NETWORK" --network-alias frpc \
    -v "$WORKDIR/frpc.toml:/etc/frp/frpc.toml:ro" "$FRPC_IMAGE" >/dev/null

await "tcp proxy" fetch http://frps:6000/

expect_body "tcp proxy reaches the backend" "frp-smoke-ok" http://frps:6000/
expect_body "http proxy reaches the backend" "frp-smoke-ok" \
    --header "Host: smoke.example.com" http://frps:8080/
# A `noweb` build would serve an empty filesystem here, so this is what proves
# the dashboard assets really were compiled into the binary.
expect_body "frps dashboard is served" '<div id="app">' \
    --header "$AUTH_HEADER" http://frps:7500/
expect_body "frpc admin UI is served" '<div id="app">' \
    --header "$AUTH_HEADER" http://frpc:7400/

echo "==> smoke test passed"
