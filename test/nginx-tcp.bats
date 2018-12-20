ALPINE="alpine:3.5"

function setup() {
  SSL_CERTIFICATE="$(cat "test/ssl/cert.pem")"
  SSL_KEY="$(cat "test/ssl/key.pem")"
}

function teardown() {
  echo "--- END TEST ---"

  for container in NGINX HTTPD HTTPD_ALT ACCEPT; do
    # Basically cid=${!container} - bats blows up if we use that form though.
    cid="$(eval echo "$`echo $container`")"
    if [[ -n "$cid" ]]; then
      echo
      echo "--- BEGIN ${container} LOGS ---"
      docker logs "$cid"
      echo "--- END ${container} LOGS ---"
      docker stop -t 1 "${container}"
    fi
  done
}

function nginx() {
  [[ -z "$NGINX" ]]
  NGINX="$(docker run --name "NGINX" -d --rm "$@" "$IMAGE")"
  NGINX_HOST="$(find_container_host "$NGINX")"
}

function httpd() {
  [[ -z "$HTTPD" ]]
  local message="${1:-"httpd"}"
  HTTPD="$(docker run  --name "HTTPD" -d --rm "$ALPINE" sh -c "echo '$message' > index.html && httpd -f")"
  HTTPD_HOST="$(find_container_host "$HTTPD")"
}

function httpd_alt() {
  [[ -z "$HTTPD_ALT" ]]
  local message="${1:-"httpd alt"}"
  HTTPD_ALT="$(docker run --name "HTTPD_ALT" -d --rm "$ALPINE" sh -c "echo '$message' > index.html && httpd -f")"
  HTTPD_ALT_HOST="$(find_container_host "$HTTPD_ALT")"
}

function accept() {
  [[ -z "$ACCEPT" ]]
  ACCEPT="$(docker run --name "ACCEPT"  -d --rm "$ALPINE" nc -l -p 123 -e sleep 100)"
  ACCEPT_HOST="$(find_container_host "$ACCEPT")"
}

function wait_container() {
  local container="${1:-"$NGINX"}"
  [[ -n "$container" ]]
  local timeout="${2:-"2"}"
  timeout -s INT -k "1" "$timeout" docker wait "$container"
}

function find_container_host() {
  docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$1"
}

function find_container_port() {
  docker port "$1" "$2" | awk '{ split($0, h , ":"); print h[2] }'
}

@test "It fails if PROXY_CONFIGURATION is unset" {
  nginx
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails if PROXY_CONFIGURATION is not JSON" {
  nginx -e "PROXY_CONFIGURATION=foo"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (bad structure)" {
  nginx -e "PROXY_CONFIGURATION=[100]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (no upstreams)" {
  nginx -e "PROXY_CONFIGURATION=[[100]]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (empty upstreams)" {
  nginx -e "PROXY_CONFIGURATION=[[100, []]]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (upstream has no port)" {
  nginx -e 'PROXY_CONFIGURATION=[[100, ["127.0.0.1"]]]'
  [[ "$(wait_container)" = 1 ]]
}

@test "It boots with an empty PROXY_CONFIGURATION" {
  nginx -e "PROXY_CONFIGURATION=[]"
  [[ -z "$(wait_container)" ]]
}

@test "It accepts connections" {
  nginx -e 'PROXY_CONFIGURATION=[[100, [["127.0.0.1", 200]]]]'
  [[ -z "$(wait_container)" ]]
  docker run --rm "$ALPINE" nc "$NGINX_HOST" 100
  docker logs "$NGINX" 2>&1 | grep "127.0.0.1:200"
}

@test "It proxies traffic" {
  canary="hello from httpd"
  httpd "$canary"
  nginx -e "PROXY_CONFIGURATION=[[100, [[\"$HTTPD_HOST\", 80]]]]"
  [[ -z "$(wait_container)" ]]

  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100" | grep "$canary"
}

@test "It proxies traffic on multiple ports" {
  canary="hello from httpd"
  httpd "$canary"
  nginx -e "PROXY_CONFIGURATION=[ [100, [[\"$HTTPD_HOST\", 80]]], [200, [[\"$HTTPD_HOST\", 80]]] ]"
  [[ -z "$(wait_container)" ]]

  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100" | grep "$canary"
  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:200" | grep "$canary"
}

@test "It does not mix up upstreams" {
  httpd "foo"
  httpd_alt "bar"
  nginx -e "PROXY_CONFIGURATION=[ [100, [[\"$HTTPD_HOST\", 80]]], [200, [[\"$HTTPD_ALT_HOST\", 80]]] ]"
  [[ -z "$(wait_container)" ]]

  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100" | grep "foo"
  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:200" | grep "bar"
}

@test "It proxies traffic to multiple upstreams" {
  httpd "foo"
  httpd_alt "bar"
  nginx -e "PROXY_CONFIGURATION=[[100, [ [\"$HTTPD_HOST\", 80], [\"$HTTPD_ALT_HOST\", 80] ]]]"
  [[ -z "$(wait_container)" ]]

  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100"
  docker stop -t 0 "$HTTPD"
  docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100"
  docker stop -t 0 "$HTTPD_ALT"
  ! docker run --rm "$ALPINE" wget -T1 -O- "${NGINX_HOST}:100"
}

@test "It enforces IDLE_TIMEOUT" {
  accept
  nginx -e "PROXY_CONFIGURATION=[[100, [[\"$ACCEPT_HOST\", 123]]]]" -e "IDLE_TIMEOUT=2"
  [[ -z "$(wait_container)" ]]
  run docker run --rm "$ALPINE" wget -T5 "${NGINX_HOST}:100"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "error getting response" ]]
  [[ ! "$output" =~ "download timed out" ]]
}

@test "It terminates SSL connections" {
  httpd "$canary"
  nginx -e "PROXY_CONFIGURATION=[[100, [[\"$HTTPD_HOST\", 80]]]]" \
        -e 'SSL=1' -e "SSL_CERTIFICATE=${SSL_CERTIFICATE}" -e "SSL_KEY=${SSL_KEY}"
  [[ -z "$(wait_container)" ]]
  run docker run --rm "$CLIENT_IMAGE" curl -kv "https://${NGINX_HOST}:100"
  [[ "$status" -eq 0 ]]
  [[ "$output" =~ "CN=test" ]]
  [[ "$output" =~ "200 OK" ]]
}

@test "It fails if SSL is enabled but the certificate is missing" {
  nginx -e 'PROXY_CONFIGURATION=[[100, [["127.0.0.1", 200]]]]' \
        -e 'SSL=1' -e "SSL_KEY=${SSL_KEY}"
  [[ "$(wait_container)" -eq 1 ]]
}

@test "It fails if SSL is enabled but the key is missing" {
  nginx -e 'PROXY_CONFIGURATION=[[100, [["127.0.0.1", 200]]]]' \
        -e 'SSL=1' -e "SSL_CERTIFICATE=${SSL_CERTIFICATE}"
  [[ "$(wait_container)" -eq 1 ]]
}
