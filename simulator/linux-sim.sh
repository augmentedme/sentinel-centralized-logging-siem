#!/usr/bin/env bash
# =====================================================================
# siem-sim: generates normal traffic and attack patterns on web-01 so the
# SIEM has realistic historical data. Installed by setup-web01.sh to
# /usr/local/bin/siem-sim and run by cron every 10 minutes.
#
#   siem-sim          normal cycle: browsing, occasional logins, a few
#                     failures, occasional scans (stays below alert thresholds)
#   siem-sim burst    attack burst: triggers the brute-force and web
#                     scanning analytics rules on demand
#
# All traffic targets this VM only (127.0.0.1).
# =====================================================================
set -uo pipefail

BASE="http://127.0.0.1"
ENV_FILE="/opt/siem/.env"
STAFF_PW="$(grep '^APP_STAFF_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"

BROWSERS=(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36"
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
  "Mozilla/5.0 (X11; Linux x86_64; rv:129.0) Gecko/20100101 Firefox/129.0"
)
FAKE_USERS=(admin root test administrator jsmith guest backup oracle support)
SCAN_PATHS=(/.env /.git/config /wp-admin/ /wp-login.php /phpmyadmin/ /xmlrpc.php /admin.php
  /config.json /cgi-bin/test.cgi /vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php
  /server-status /.aws/credentials)
PAGES=(/ /login /health)

rand() { echo $((RANDOM % $1)); }
pick() { local items=("$@"); echo "${items[$(rand ${#items[@]})]}"; }

browse() {
  local count=$((3 + $(rand 5)))
  for _ in $(seq 1 "$count"); do
    curl -s -o /dev/null -A "$(pick "${BROWSERS[@]}")" "$BASE$(pick "${PAGES[@]}")"
  done
}

good_session() {
  local jar ua
  jar="$(mktemp)"
  ua="$(pick "${BROWSERS[@]}")"
  curl -s -o /dev/null -c "$jar" -b "$jar" -A "$ua" \
    --data-urlencode "username=staff" --data-urlencode "password=$STAFF_PW" "$BASE/login"
  curl -s -o /dev/null -b "$jar" -A "$ua" "$BASE/dashboard"
  # A staff user trying the admin page produces an access_denied audit event.
  [[ $(rand 2) -eq 0 ]] && curl -s -o /dev/null -b "$jar" -A "$ua" "$BASE/admin"
  curl -s -o /dev/null -b "$jar" -A "$ua" "$BASE/logout"
  rm -f "$jar"
}

failed_logins() {
  for _ in $(seq 1 "$1"); do
    curl -s -o /dev/null -A "python-requests/2.32.3" \
      --data-urlencode "username=$(pick "${FAKE_USERS[@]}")" \
      --data-urlencode "password=Password$(rand 10000)" "$BASE/login"
  done
}

scan() {
  for _ in $(seq 1 "$1"); do
    curl -s -o /dev/null -A "Mozilla/5.0 zgrab/0.x" "$BASE$(pick "${SCAN_PATHS[@]}")"
  done
}

ssh_invalid_users() {
  # Key-only SSH: invalid usernames are logged by sshd as "Invalid user".
  for _ in $(seq 1 "$1"); do
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 "$(pick "${FAKE_USERS[@]}")@127.0.0.1" true >/dev/null 2>&1
  done
}

case "${1:-normal}" in
  burst)
    failed_logins 12
    scan 15
    ssh_invalid_users 6
    ;;
  *)
    browse
    [[ $(rand 3) -eq 0 ]] && good_session
    failed_logins "$(rand 3)"
    [[ $(rand 4) -eq 0 ]] && scan $((1 + $(rand 4)))
    [[ $(rand 3) -eq 0 ]] && ssh_invalid_users $((1 + $(rand 2)))
    ;;
esac
exit 0
