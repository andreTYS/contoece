#!/bin/bash
# SSL setup via certbot webroot for oece.masredespro.com
# Run this on the VPS as root after deploying updated containers.
set -e

DOMAIN="oece.masredespro.com"
EMAIL="andretys1000@gmail.com"
REPO_DIR="/home/user/CONTRATACIONES"

echo "=== Step 1: Ensure /var/www/certbot exists ==="
mkdir -p /var/www/certbot

echo "=== Step 2: Deploy updated containers ==="
cd "$REPO_DIR"
git pull origin claude/flutter-ai-chatbot-app-rwbuu
docker compose down
docker compose up -d --build

echo "Waiting 10s for containers to start..."
sleep 10

echo "=== Step 3: Install certbot ==="
apt-get update -qq
apt-get install -y certbot

echo "=== Step 4: Obtain certificate via HTTP-01 webroot ==="
certbot certonly \
  --webroot \
  -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --non-interactive

echo "=== Step 5: Configure Traefik to use the certbot cert ==="

# Find n8n traefik compose location from its Labels or Mounts
TRAEFIK_DIR=$(docker inspect n8n-traefik-1 \
  --format '{{range .Mounts}}{{if eq .Destination "/letsencrypt"}}{{.Source}}{{end}}{{end}}' \
  | xargs dirname 2>/dev/null || echo "")

if [ -z "$TRAEFIK_DIR" ]; then
  # Try common locations
  for D in /root/n8n /home/user/n8n /opt/n8n /root /home/user; do
    if [ -f "$D/docker-compose.yml" ] && grep -q "traefik" "$D/docker-compose.yml" 2>/dev/null; then
      TRAEFIK_DIR="$D"
      break
    fi
  done
fi

if [ -z "$TRAEFIK_DIR" ]; then
  echo ""
  echo "=== ACTION REQUIRED: Traefik compose not auto-detected ==="
  echo "Find your n8n/traefik docker-compose.yml and run:"
  echo ""
  echo "  1. Create dynamic config dir:"
  echo "     mkdir -p <traefik-dir>/traefik-dynamic"
  echo ""
  echo "  2. Create cert config:"
  echo "     cat > <traefik-dir>/traefik-dynamic/certs.yml << 'EOF'"
  echo "tls:"
  echo "  certificates:"
  echo "    - certFile: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
  echo "      keyFile: /etc/letsencrypt/live/$DOMAIN/privkey.pem"
  echo "EOF"
  echo ""
  echo "  3. Add to n8n traefik docker-compose.yml service volumes:"
  echo "     - /etc/letsencrypt:/etc/letsencrypt:ro"
  echo "     - ./traefik-dynamic:/etc/traefik/dynamic:ro"
  echo ""
  echo "  4. Add to traefik command:"
  echo "     - --providers.file.directory=/etc/traefik/dynamic"
  echo "     - --providers.file.watch=true"
  echo ""
  echo "  5. Restart: docker compose down && docker compose up -d"
  exit 0
fi

echo "Found Traefik dir: $TRAEFIK_DIR"

mkdir -p "$TRAEFIK_DIR/traefik-dynamic"
cat > "$TRAEFIK_DIR/traefik-dynamic/certs.yml" << EOF
tls:
  certificates:
    - certFile: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
      keyFile: /etc/letsencrypt/live/$DOMAIN/privkey.pem
EOF

echo "Created $TRAEFIK_DIR/traefik-dynamic/certs.yml"
echo ""
echo "=== MANUAL STEP: Update n8n traefik docker-compose ==="
echo "Add these lines to the n8n-traefik service in $TRAEFIK_DIR/docker-compose.yml:"
echo ""
echo "  volumes (add):"
echo "    - /etc/letsencrypt:/etc/letsencrypt:ro"
echo "    - ./traefik-dynamic:/etc/traefik/dynamic:ro"
echo ""
echo "  command (add):"
echo "    - '--providers.file.directory=/etc/traefik/dynamic'"
echo "    - '--providers.file.watch=true'"
echo ""
echo "Then restart: cd $TRAEFIK_DIR && docker compose down && docker compose up -d"
echo ""

echo "=== Step 6: Setup auto-renewal cron ==="
cat > /etc/cron.d/certbot-oece << 'CRON'
0 3 * * * root certbot renew --quiet --webroot -w /var/www/certbot && docker restart oece-ia-web
CRON

echo "Auto-renewal cron installed at /etc/cron.d/certbot-oece"
echo ""
echo "=== Done! Follow the manual step above to activate the cert in Traefik. ==="
