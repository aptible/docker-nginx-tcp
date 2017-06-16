function setup() {
  true
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
      docker rm -f "$cid"
    fi
  done
}

function nginx() {
  [[ -z "$NGINX" ]]
  NGINX="$(docker run -d "$@" "$IMAGE")"
  NGINX_HOST="$(find_container_host "$NGINX")"
}

function httpd() {
  [[ -z "$HTTPD" ]]
  local message="${1:-"httpd"}"
  HTTPD="$(docker run -d alpine sh -c "echo '$message' > index.html && httpd -f")"
  HTTPD_HOST="$(find_container_host "$HTTPD")"
}

function httpd_alt() {
  [[ -z "$HTTPD_ALT" ]]
  local message="${1:-"httpd alt"}"
  HTTPD_ALT="$(docker run -d alpine sh -c "echo '$message' > index.html && httpd -f")"
  HTTPD_ALT_HOST="$(find_container_host "$HTTPD_ALT")"
}

function accept() {
  [[ -z "$ACCEPT" ]]
  ACCEPT="$(docker run -d alpine nc -l -p 123 -e sleep 100)"
  ACCEPT_HOST="$(find_container_host "$ACCEPT")"
}

function wait_container() {
  [[ -n "$NGINX" ]]
  local timeout="${1:-"2"}"
  timeout -s INT -k "1" "$timeout" docker wait "$NGINX"
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
  nginx -e "PROXY_CONFIGURATION=[10]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (no upstreams)" {
  nginx -e "PROXY_CONFIGURATION=[[10]]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (empty upstreams)" {
  nginx -e "PROXY_CONFIGURATION=[[10, []]]"
  [[ "$(wait_container)" = 1 ]]
}

@test "It fails with a malformed PROXY_CONFIGURATION (upstream has no port)" {
  nginx -e 'PROXY_CONFIGURATION=[[10, ["127.0.0.1"]]]'
  [[ "$(wait_container)" = 1 ]]
}

@test "It boots with an empty PROXY_CONFIGURATION" {
  nginx -e "PROXY_CONFIGURATION=[]"
  [[ -z "$(wait_container)" ]]
}

@test "It accepts connections" {
  nginx -e 'PROXY_CONFIGURATION=[[10, [["127.0.0.1", 20]]]]'
  [[ -z "$(wait_container)" ]]
  docker run --rm alpine nc "$NGINX_HOST" 10
  docker logs "$NGINX" 2>&1 | grep "127.0.0.1:20"
}

@test "It proxies traffic" {
  canary="hello from httpd"
  httpd "$canary"
  nginx -e "PROXY_CONFIGURATION=[[10, [[\"$HTTPD_HOST\", 80]]]]"
  [[ -z "$(wait_container)" ]]

  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10" | grep "$canary"
}

@test "It proxies traffic on multiple ports" {
  canary="hello from httpd"
  httpd "$canary"
  nginx -e "PROXY_CONFIGURATION=[ [10, [[\"$HTTPD_HOST\", 80]]], [20, [[\"$HTTPD_HOST\", 80]]] ]"
  [[ -z "$(wait_container)" ]]

  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10" | grep "$canary"
  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:20" | grep "$canary"
}

@test "It does not mix up upstreams" {
  httpd "foo"
  httpd_alt "bar"
  nginx -e "PROXY_CONFIGURATION=[ [10, [[\"$HTTPD_HOST\", 80]]], [20, [[\"$HTTPD_ALT_HOST\", 80]]] ]"
  [[ -z "$(wait_container)" ]]

  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10" | grep "foo"
  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:20" | grep "bar"
}

@test "It proxies traffic to multiple upstreams" {
  httpd "foo"
  httpd_alt "bar"
  nginx -e "PROXY_CONFIGURATION=[[10, [ [\"$HTTPD_HOST\", 80], [\"$HTTPD_ALT_HOST\", 80] ]]]"
  [[ -z "$(wait_container)" ]]

  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10"
  docker stop -t 0 "$HTTPD"
  docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10"
  docker stop -t 0 "$HTTPD_ALT"
  ! docker run --rm alpine wget -T1 -O- "${NGINX_HOST}:10"
}

@test "It enforces IDLE_TIMEOUT" {
  accept
  nginx -e "PROXY_CONFIGURATION=[[10, [[\"$ACCEPT_HOST\", 123]]]]" -e "IDLE_TIMEOUT=2"
  [[ -z "$(wait_container)" ]]
  run docker run --rm alpine wget -T5 "${NGINX_HOST}:10"
  [[ "$status" -eq 1 ]]
  [[ "$output" =~ "error getting response" ]]
  [[ ! "$output" =~ "download timed out" ]]
}
