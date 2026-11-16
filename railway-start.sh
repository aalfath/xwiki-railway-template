#!/bin/bash
# Railway wrapper for the official XWiki image (https://hub.docker.com/_/xwiki).
#
# Every boot: map the template's variables to the image's DB_* settings, make Tomcat
# listen on $PORT and trust Railway's HTTPS proxy headers, then run the upstream
# entrypoint (docker-entrypoint.sh xwiki).
#
# First boot only (no marker on the volume), while Tomcat listens on localhost only
# and a placeholder page answers on $PORT:
#   1. create the first administrator ($XWIKI_ADMIN_USER / $XWIKI_ADMIN_PASSWORD)
#      through XWiki's own Distribution Wizard step,
#   2. install the standard XWiki flavor (the default wiki pages and apps)
#      non-interactively,
# so nobody can claim or edit the wiki before you log in.
set -euo pipefail

export PORT="${PORT:-8080}"
export DB_HOST="${DB_HOST:-${PGHOST:-db}}"
export DB_PORT="${DB_PORT:-${PGPORT:-5432}}"
export DB_USER="${DB_USER:-${PGUSER:-xwiki}}"
export DB_PASSWORD="${DB_PASSWORD:-${PGPASSWORD:-xwiki}}"
export DB_DATABASE="${DB_DATABASE:-${PGDATABASE:-xwiki}}"
XWIKI_ADMIN_USER="${XWIKI_ADMIN_USER:-Admin}"
XWIKI_ADMIN_PASSWORD="${XWIKI_ADMIN_PASSWORD:-}"
XWIKI_FLAVOR="${XWIKI_FLAVOR:-org.xwiki.platform:xwiki-platform-distribution-flavor-mainwiki}"

WEBINF=/usr/local/tomcat/webapps/ROOT/WEB-INF
DATA=/usr/local/xwiki/data
ADMIN_MARKER="$DATA/.railway-admin-created"
FLAVOR_MARKER="$DATA/.railway-flavor-installed"
SERVER_XML=/usr/local/tomcat/conf/server.xml
BOOT_PORT=8099
BOOT_LOG=/tmp/xwiki-bootstrap.log
base="http://127.0.0.1:${BOOT_PORT}"

log() { echo "[railway-start] $*"; }

# Tomcat connector on the given port (and address), plus RemoteIpValve so XWiki sees https.
write_server_xml() {
  local port="$1" address="${2:-}" attr=""
  if [ -n "$address" ]; then attr=" address=\"${address}\""; fi
  sed -e "s#<Connector port=\"8080\" protocol=\"HTTP/1.1\"#<Connector port=\"${port}\"${attr} protocol=\"HTTP/1.1\"#" \
      -e 's#</Host>#  <Valve className="org.apache.catalina.valves.RemoteIpValve" internalProxies=".*" remoteIpHeader="x-forwarded-for" protocolHeader="x-forwarded-proto" />\n      </Host>#' \
      /usr/local/tomcat/conf/server.xml.orig > "$SERVER_XML"
  grep -q "port=\"${port}\"${attr} protocol" "$SERVER_XML" || { log "could not set the Tomcat port"; exit 1; }
}

# Set KEY=VALUE in xwiki.properties (replaces the commented default, else appends).
set_prop() {
  local f="$WEBINF/xwiki.properties"
  if grep -qE "^#? ?$1 ?=" "$f"; then
    sed -i -E "s~^#? ?$1 ?=.*~$1=$2~" "$f"
  else
    echo "$1=$2" >> "$f"
  fi
}

wait_for_db() {
  for i in $(seq 1 90); do
    if (exec 3<>"/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; then return 0; fi
    log "waiting for PostgreSQL at ${DB_HOST}:${DB_PORT} ($i)"; sleep 2
  done
  log "PostgreSQL is not reachable"; exit 1
}

PLACEHOLDER_PID=""
start_placeholder() {
  mkdir -p /tmp/placeholder/rest
  cat > /tmp/placeholder/index.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="20"><title>XWiki is being set up</title></head>
<body style="font-family:sans-serif;max-width:40em;margin:4em auto">
<h1>XWiki is being set up</h1>
<p>The first start creates the administrator account and installs the standard XWiki flavor. This takes a few minutes. This page reloads on its own.</p>
<p>Log in afterwards with the user and password in the XWiki service's <code>XWIKI_ADMIN_USER</code> and <code>XWIKI_ADMIN_PASSWORD</code> variables.</p>
</body></html>
HTML
  cp /tmp/placeholder/index.html /tmp/placeholder/rest/index.html
  busybox httpd -f -p "$PORT" -h /tmp/placeholder &
  PLACEHOLDER_PID=$!
}
stop_placeholder() {
  if [ -n "$PLACEHOLDER_PID" ]; then kill "$PLACEHOLDER_PID" 2>/dev/null || true; wait "$PLACEHOLDER_PID" 2>/dev/null || true; PLACEHOLDER_PID=""; fi
}

XPID=""
start_local_xwiki() {
  write_server_xml "$BOOT_PORT" "127.0.0.1"
  docker-entrypoint.sh xwiki >> "$BOOT_LOG" 2>&1 &
  XPID=$!
}
stop_local_xwiki() {
  /usr/local/tomcat/bin/catalina.sh stop 60 >/dev/null 2>&1 || true
  for i in $(seq 1 90); do kill -0 "$XPID" 2>/dev/null || break; sleep 1; done
  kill "$XPID" 2>/dev/null || true
  wait "$XPID" 2>/dev/null || true
}
fail() { tail -n 60 "$BOOT_LOG" || true; log "$*"; stop_local_xwiki; stop_placeholder; exit 1; }

# Wait until the given local URL answers with one of the given codes.
wait_for() {
  local url="$1" codes="$2" tries="${3:-180}"
  for i in $(seq 1 "$tries"); do
    kill -0 "$XPID" 2>/dev/null || fail "XWiki stopped during first boot"
    local code; code=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ " $codes " == *" $code "* ]]; then return 0; fi
    sleep 5
  done
  fail "XWiki did not answer on $url"
}

wait_for_db
mkdir -p "$DATA"
set_prop distribution.defaultUI "$XWIKI_FLAVOR"

if [ ! -f "$ADMIN_MARKER" ] || [ ! -f "$FLAVOR_MARKER" ]; then
  [ -n "$XWIKI_ADMIN_PASSWORD" ] || { log "XWIKI_ADMIN_PASSWORD is empty: set it, then redeploy."; exit 1; }
  start_placeholder
fi

if [ ! -f "$ADMIN_MARKER" ]; then
  log "first boot (1/2): creating the administrator '${XWIKI_ADMIN_USER}' (XWiki on localhost only)"
  start_local_xwiki
  dw="$base/bin/distribution/XWiki/Distribution"
  wait_for "$dw" "200"
  # Welcome step: continue. Admin user step: register the first administrator (also made wiki owner).
  curl -s -o /dev/null -c /tmp/dw.cookies -b /tmp/dw.cookies "$dw" --data "action=COMPLETE_STEP" || true
  curl -s -o /dev/null -c /tmp/dw.cookies -b /tmp/dw.cookies "$dw" \
    --data-urlencode "xwikiname=${XWIKI_ADMIN_USER}" \
    --data-urlencode "register_password=${XWIKI_ADMIN_PASSWORD}" \
    --data-urlencode "register2_password=${XWIKI_ADMIN_PASSWORD}" \
    --data-urlencode "register_first_name=${XWIKI_ADMIN_USER}" \
    --data-urlencode "register_email=${XWIKI_ADMIN_EMAIL:-admin@example.com}" || true
  rm -f /tmp/dw.cookies
  # Check the account by logging in with it (302 + username cookie on success, 403 on failure).
  hdrs=$(curl -s -o /dev/null -D - "$base/bin/loginsubmit/XWiki/XWikiLogin" \
       --data-urlencode "j_username=${XWIKI_ADMIN_USER}" --data-urlencode "j_password=${XWIKI_ADMIN_PASSWORD}" || true)
  if ! grep -qi '^set-cookie: username=' <<<"$hdrs"; then
    code=$(curl -s -o /dev/null -w '%{http_code}' "$base/rest/wikis/xwiki/spaces/XWiki/pages/${XWIKI_ADMIN_USER}" || true)
    [ "$code" = "200" ] || fail "could not create the administrator '${XWIKI_ADMIN_USER}'"
    log "the user '${XWIKI_ADMIN_USER}' already exists (its password may have been changed); keeping it"
  fi
  touch "$ADMIN_MARKER"
  log "administrator '${XWIKI_ADMIN_USER}' is ready"
  stop_local_xwiki
fi

if [ ! -f "$FLAVOR_MARKER" ]; then
  log "first boot (2/2): installing the XWiki flavor ${XWIKI_FLAVOR} (downloads from the XWiki extension repository, a few minutes)"
  set_prop distribution.job.interactive false
  : > "$BOOT_LOG"
  start_local_xwiki
  wait_for "$base/rest/" "200"
  # The Distribution Wizard job runs on its own (non-interactive); poll its status as the administrator.
  state=""
  for i in $(seq 1 240); do
    kill -0 "$XPID" 2>/dev/null || fail "XWiki stopped while installing the flavor"
    state=$(curl -s -u "${XWIKI_ADMIN_USER}:${XWIKI_ADMIN_PASSWORD}" "$base/rest/jobstatus/distribution" \
            | sed -n 's#.*<state>\([A-Z_]*\)</state>.*#\1#p' || true)
    if [ "$state" = "FINISHED" ]; then break; fi
    # Fallback when the administrator's password was changed: the flavor install job's log line.
    if grep -q "Finished job of type \[install\] with identifier \[\[extension, action, ${XWIKI_FLAVOR}," "$BOOT_LOG"; then
      sleep 20; state=FINISHED; break
    fi
    sleep 5
  done
  [ "$state" = "FINISHED" ] || fail "the flavor installation did not finish in 20 minutes"
  if grep -q "Failed to install\|Failed to apply \[INSTALL\]" "$BOOT_LOG"; then
    fail "the flavor installation reported errors"
  fi
  touch "$FLAVOR_MARKER"
  log "flavor installed"
  stop_local_xwiki
  set_prop distribution.job.interactive true
fi

stop_placeholder
write_server_xml "$PORT"
log "starting XWiki on port ${PORT}"
exec docker-entrypoint.sh xwiki
