#!/usr/bin/env bash
set -euo pipefail

# Start the full Homebot local dev stack.
# Usage: bash ~/.claude/skills/local-dev/start.sh [status|down]

HBDEV_DIR="$HOME/Sites/homebotapp/hbdev"
SURFACES_DIR="$HOME/Sites/homebotapp/surfaces"
LOCKBOX_DIR="$HOME/Sites/homebotapp/lockbox"
MIKASA_DIR="$HOME/Sites/homebotapp/mikasa"
CUSTOMER_ADMIN_DIR="$HOME/Sites/homebotapp/customer-admin"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_service() {
  local name="$1"
  local check="$2"
  if eval "$check" 2>/dev/null; then
    echo -e "  ${GREEN}${name}${NC}"
    return 0
  else
    echo -e "  ${RED}${name}${NC}"
    return 1
  fi
}

status() {
  echo "Local Dev Status"
  echo "────────────────"

  check_service "Colima" "colima list 2>/dev/null | grep -q Running" || true
  check_service "hbdev" "docker ps --format '{{.Names}}' | grep -q hbdev_traefik" || true
  check_service "surfaces-db" "docker ps --format '{{.Names}}' | grep -q ai-mastra-postgres" || true
  check_service "lockbox" "docker ps --format '{{.Names}}' | grep -q '^lockbox$'" || true
  check_service "mikasa" "docker ps --format '{{.Names}}' | grep -q '^mikasa$'" || true
  check_service "customer-admin" "docker ps --format '{{.Names}}' | grep -q customer-admin" || true

  echo ""
  echo -e "${YELLOW}Surfaces app runs locally: cd ~/Sites/homebotapp/surfaces && pnpm dev${NC}"
}

start() {
  echo "Starting local dev stack..."
  echo ""

  # 1. Colima
  if colima list 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}Colima already running${NC}"
  else
    echo "Starting Colima..."
    colima start
  fi

  # 2. hbdev
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q hbdev_traefik; then
    echo -e "${GREEN}hbdev already running${NC}"
  else
    echo "Starting hbdev..."
    docker compose -f "$HBDEV_DIR/docker-compose.yml" -p hbdev up -d 2>&1 | tail -5
  fi

  # 3. surfaces-db
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q ai-mastra-postgres; then
    echo -e "${GREEN}surfaces-db already running${NC}"
  else
    echo "Starting surfaces-db..."
    (cd "$SURFACES_DIR" && docker compose up -d 2>&1 | tail -3)
  fi

  # 4. lockbox
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^lockbox$'; then
    echo -e "${GREEN}lockbox already running${NC}"
  else
    echo "Starting lockbox..."
    (cd "$LOCKBOX_DIR" && docker compose up -d 2>&1 | tail -3)
    echo "Waiting for lockbox..."
    for i in $(seq 1 60); do
      if docker logs --tail 1 lockbox 2>&1 | grep -q "Listening on"; then
        echo -e "${GREEN}lockbox ready${NC}"
        break
      fi
      sleep 2
    done
  fi

  # 5. mikasa
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^mikasa$'; then
    echo -e "${GREEN}mikasa already running${NC}"
  else
    echo "Starting mikasa..."
    (cd "$MIKASA_DIR" && docker compose up -d 2>&1 | tail -3)
    echo "Waiting for mikasa..."
    for i in $(seq 1 60); do
      if docker logs --tail 1 mikasa 2>&1 | grep -q "Listening on"; then
        echo -e "${GREEN}mikasa ready${NC}"
        break
      fi
      sleep 2
    done
  fi

  # 6. customer-admin
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q customer-admin; then
    echo -e "${GREEN}customer-admin already running${NC}"
  else
    echo "Starting customer-admin..."
    (cd "$CUSTOMER_ADMIN_DIR" && docker compose up -d 2>&1 | tail -3)
    echo "Waiting for customer-admin..."
    for i in $(seq 1 60); do
      if docker logs --tail 1 customer-admin-customer-admin-1 2>&1 | grep -q "Ready"; then
        echo -e "${GREEN}customer-admin ready${NC}"
        break
      fi
      sleep 2
    done
  fi

  echo ""
  echo "=== Health Checks ==="
  curl -sk -o /dev/null -w "Traefik:        %{http_code}\n" https://traefik.homebot.test
  curl -sk -o /dev/null -w "Elasticsearch:  %{http_code}\n" https://es.homebot.test
  curl -sk -o /dev/null -w "Lockbox:        %{http_code}\n" https://sso.homebot.test
  curl -sk -o /dev/null -w "Mikasa:         %{http_code}\n" https://mikasa.homebot.test
  curl -sk -o /dev/null -w "Customer Admin: %{http_code}\n" https://customer-admin.homebot.test/en

  echo ""
  echo -e "${YELLOW}Surfaces app runs locally: cd ~/Sites/homebotapp/surfaces && pnpm dev${NC}"
}

stop() {
  echo "Stopping local dev stack..."
  echo ""

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q customer-admin; then
    echo "Stopping customer-admin..."
    (cd "$CUSTOMER_ADMIN_DIR" && docker compose down 2>&1 | tail -3)
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^mikasa'; then
    echo "Stopping mikasa..."
    (cd "$MIKASA_DIR" && docker compose down 2>&1 | tail -3)
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^lockbox'; then
    echo "Stopping lockbox..."
    (cd "$LOCKBOX_DIR" && docker compose down 2>&1 | tail -3)
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q ai-mastra; then
    echo "Stopping surfaces-db..."
    (cd "$SURFACES_DIR" && docker compose down 2>&1 | tail -3)
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q hbdev; then
    echo "Stopping hbdev..."
    docker compose -f "$HBDEV_DIR/docker-compose.yml" -p hbdev down 2>&1 | tail -3
  fi

  if colima list 2>/dev/null | grep -q Running; then
    echo "Stopping Colima..."
    colima stop
  fi

  echo ""
  echo -e "${GREEN}All stopped.${NC}"
}

case "${1:-start}" in
  status) status ;;
  down|stop) stop ;;
  start|up|"") start ;;
  *)
    echo "Usage: $0 [status|start|down]"
    exit 1
    ;;
esac

