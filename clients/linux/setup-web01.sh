#!/usr/bin/env bash
# =====================================================================
# setup-web01.sh: configures the Linux log source VM (web-01).
#
#   - Nginx reverse proxy with a JSON access log       (web server)
#   - Staff Portal Flask app in a hardened container   (web application, container)
#   - Log rotation for the collected files
#   - Host firewall (defence in depth behind the Azure NSG)
#   - Traffic and attack simulator on a 10-minute cron schedule
#
# Usage (on web-01):  sudo bash ~/siem/clients/linux/setup-web01.sh
# Safe to re-run: existing secrets are kept.
# =====================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo." >&2
  exit 1
fi

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_DIR="/opt/siem"
ENV_FILE="$INSTALL_DIR/.env"
APP_UID=10001

step() { echo -e "\n==> $*"; }

step "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y nginx docker.io docker-compose-v2 rsyslog curl openssl ufw logrotate
systemctl enable --now docker rsyslog nginx

step "Copying project files to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
if [[ "$SRC_DIR" != "$INSTALL_DIR" ]]; then
  cp -r "$SRC_DIR/app" "$SRC_DIR/clients" "$SRC_DIR/simulator" "$INSTALL_DIR/"
fi
# Defensive: strip Windows line endings in case files were edited on Windows.
find "$INSTALL_DIR" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.yml' \
  -o -name '*.conf' -o -name 'Dockerfile' -o -name 'logrotate-siem' \) -exec sed -i 's/\r$//' {} +

step "Generating application secrets (kept if they already exist)"
if [[ ! -f "$ENV_FILE" ]]; then
  {
    echo "FLASK_SECRET_KEY=$(openssl rand -hex 32)"
    echo "APP_ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
    echo "APP_STAFF_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
  } > "$ENV_FILE"
fi
chown root:root "$ENV_FILE"
chmod 600 "$ENV_FILE"

step "Preparing the application audit log directory"
mkdir -p /var/log/webapp
chown "$APP_UID:$APP_UID" /var/log/webapp
chmod 755 /var/log/webapp

step "Building and starting the Staff Portal container"
docker compose -f "$INSTALL_DIR/clients/linux/docker-compose.yml" up -d --build

step "Configuring Nginx"
install -m 644 "$INSTALL_DIR/clients/linux/nginx-siem.conf" /etc/nginx/sites-available/siem
ln -sf /etc/nginx/sites-available/siem /etc/nginx/sites-enabled/siem
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx
install -m 644 "$INSTALL_DIR/clients/linux/logrotate-siem" /etc/logrotate.d/siem

step "Enabling host firewall (SSH and HTTP only)"
ufw allow OpenSSH
ufw allow 'Nginx HTTP'
ufw --force enable

step "Installing the traffic simulator (runs every 10 minutes)"
install -m 755 "$INSTALL_DIR/simulator/linux-sim.sh" /usr/local/bin/siem-sim
echo '*/10 * * * * root /usr/local/bin/siem-sim >/dev/null 2>&1' > /etc/cron.d/siem-sim
chmod 644 /etc/cron.d/siem-sim

step "Health check"
sleep 5
if curl -fsS http://127.0.0.1/health >/dev/null; then
  echo "Staff Portal is responding through Nginx."
else
  echo "WARNING: health check failed. Check: docker logs webapp ; sudo nginx -t" >&2
fi

echo
echo "Setup complete."
echo "Application passwords are in $ENV_FILE (root only)."
echo "View them with: sudo cat $ENV_FILE   and store them in your password manager."
