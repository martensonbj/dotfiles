#!/usr/bin/env bash
set -euo pipefail

# Homebot local dev host configuration
# Run with: sudo bash ~/Sites/homebotapp/hbdev/setup-host.sh

if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run with sudo"
  exit 1
fi

echo "==> Step 1: Adding homebot.test DNS entries to /etc/hosts"

HOMEBOT_HOSTS=(
  admin.homebot.test
  admin-v2.homebot.test
  analytics.homebot.test
  api.homebot.test
  assets.homebot.test
  c.homebot.test
  customer-admin.homebot.test
  email-templater.homebot.test
  enterprise-admin.homebot.test
  buyers.homebot.test
  hbadmin.homebot.test
  integration-bridge.homebot.test
  join.homebot.test
  mikasa.homebot.test
  sso.homebot.test
  storybook.homebot.test
  purl.homebot.test
  importer.homebot.test
  porthole.homebot.test
  es.homebot.test
  kibana.homebot.test
  mail.homebot.test
  smtp.homebot.test
  surfaces-lab-next.homebot.test
  traefik.homebot.test
)

added=0
for host in "${HOMEBOT_HOSTS[@]}"; do
  if ! grep -q "$host" /etc/hosts; then
    echo "127.0.0.1 $host" >> /etc/hosts
    ((added++))
  fi
done

if [[ $added -eq 0 ]]; then
  echo "    Skipped — all entries already exist"
else
  echo "    Added $added entries"
fi

echo "==> Step 2: Installing TLS certificate"

if security find-certificate -c "homebot" /Library/Keychains/System.keychain > /dev/null 2>&1; then
  echo "    Skipped — certificate already installed"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  CA_PEM="${SCRIPT_DIR}/.infra/tls/ca.pem"

  if [[ ! -f "$CA_PEM" ]]; then
    echo "    Error: ca.pem not found at ${CA_PEM}"
    exit 1
  fi

  security add-trusted-cert -d -r trustRoot \
    -k "/Library/Keychains/System.keychain" \
    "$CA_PEM"
  echo "    Done"
fi

echo "==> Step 3: Creating loopback alias (10.254.254.254)"

PLIST="/Library/LaunchDaemons/com.homebotapp.loopback1.plist"

if [[ -f "$PLIST" ]]; then
  echo "    Skipped — LaunchDaemon already exists"
else
  cat > "$PLIST" << 'PLIST_CONTENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.homebotapp.loopback1</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/ifconfig</string>
        <string>lo0</string>
        <string>alias</string>
        <string>10.254.254.254</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
  </dict>
</plist>
PLIST_CONTENT
  echo "    Done"
fi

if ! ifconfig lo0 | grep -q "10.254.254.254"; then
  launchctl load "$PLIST"
  echo "    Loopback alias loaded"
else
  echo "    Loopback alias already active"
fi

echo ""
echo "==> Verification"
echo -n "    /etc/hosts:    "; grep -c "homebot.test" /etc/hosts; echo " entries"
echo -n "    TLS cert:      "; security find-certificate -c "homebot" /Library/Keychains/System.keychain > /dev/null 2>&1 && echo "OK" || echo "MISSING"
echo -n "    Loopback:      "; ifconfig lo0 | grep -q "10.254.254.254" && echo "OK" || echo "MISSING"
echo ""
echo "All done!"
