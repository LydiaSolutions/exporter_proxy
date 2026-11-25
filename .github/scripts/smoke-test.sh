#!/usr/bin/env bash
set -euo pipefail

binary=${1:?usage: smoke-test.sh /path/to/exporter_proxy}
tmp_dir=$(mktemp -d)
http_backend_pid=
https_backend_pid=
proxy_pid=

cleanup() {
  if [[ -n "$proxy_pid" ]]; then
    kill -TERM "$proxy_pid" 2>/dev/null || true
    wait "$proxy_pid" 2>/dev/null || true
  fi
  for pid in "$http_backend_pid" "$https_backend_pid"; do
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

run_check() {
  local name=$1
  shift
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name" >&2
    return 1
  fi
}

check_proxy_tls() {
  for _ in $(seq 1 40); do
    if curl --insecure --fail --silent \
      "https://127.0.0.1:19099/included/metrics" \
      > "$tmp_dir/tls.out" 2>/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

check_included_exporter() {
  curl --insecure --fail --silent \
    "https://127.0.0.1:19099/included/metrics" \
    > "$tmp_dir/included.out" \
    && grep -q '^ci_http_backend 1$' "$tmp_dir/included.out"
}

check_inline_exporter_with_self_signed_backend() {
  curl --insecure --fail --silent \
    "https://127.0.0.1:19099/inline/metrics" \
    > "$tmp_dir/inline.out" \
    && grep -q '^ci_https_backend 1$' "$tmp_dir/inline.out"
}

check_query_forwarding() {
  curl --insecure --fail --silent --output /dev/null \
    "https://127.0.0.1:19099/included/metrics?check=1" \
    && grep -q 'GET /metrics?check=1 HTTP/1.1' "$tmp_dir/http-backend.log"
}

check_access_logging() {
  grep -q 'status:200' "$tmp_dir/access.log" \
    && grep -q 'path:/included/metrics' "$tmp_dir/access.log" \
    && grep -q 'query:check=1' "$tmp_dir/access.log"
}

check_error_logging() {
  grep -q 'INFO: ExporterProxy' "$tmp_dir/error.log"
}

check_graceful_shutdown() {
  kill -TERM "$proxy_pid" \
    && wait "$proxy_pid" \
    && proxy_pid=
}

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$tmp_dir/test.key" \
  -out "$tmp_dir/test.crt" \
  -days 1 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=IP:127.0.0.1" \
  > /dev/null 2>&1

python3 -m http.server 19100 \
  --bind 127.0.0.1 \
  --directory "$PWD/.github/fixtures/http" \
  > "$tmp_dir/http-backend.log" 2>&1 &
http_backend_pid=$!

(
  cd .github/fixtures/https
  exec openssl s_server \
    -accept 127.0.0.1:19101 \
    -cert "$tmp_dir/test.crt" \
    -key "$tmp_dir/test.key" \
    -quiet \
    -WWW
) > "$tmp_dir/https-backend.log" 2>&1 &
https_backend_pid=$!

mkdir -p "$tmp_dir/config/exporters.d"
cat > "$tmp_dir/config/exporters.d/included.yml" <<'YAML'
included:
  path: "/included/metrics"
  url: "http://127.0.0.1:19100/metrics"
YAML

cat > "$tmp_dir/config/config.yml" <<YAML
listen: "127.0.0.1:19099"
tls:
  certfile: "$tmp_dir/test.crt"
  keyfile: "$tmp_dir/test.key"
access_log:
  format: "ltsv"
  path: "$tmp_dir/access.log"
  fields: ["status", "path", "query", "method"]
error_log:
  path: "$tmp_dir/error.log"
shutdown_timeout: 5s
exporters:
  include: exporters.d
  inline_tls:
    path: "/inline/metrics"
    url: "https://127.0.0.1:19101/metrics"
    insecure_skip_verify: true
YAML

"$binary" -config "$tmp_dir/config/config.yml" &
proxy_pid=$!

run_check "proxy TLS listener" check_proxy_tls
run_check "exporter loaded from include directory" check_included_exporter
run_check "inline exporter with self-signed HTTPS backend" check_inline_exporter_with_self_signed_backend
run_check "query string forwarded to backend" check_query_forwarding
run_check "LTSV access logging" check_access_logging
run_check "configured error log" check_error_logging
run_check "graceful SIGTERM shutdown" check_graceful_shutdown

kill -TERM "$http_backend_pid" "$https_backend_pid" 2>/dev/null || true
wait "$http_backend_pid" "$https_backend_pid" 2>/dev/null || true
echo "integration smoke check passed"
