#!/usr/bin/env bash
# Wazuh manager entrypoint for Railway.
# 1. Adapts the image's multi-volume persistence layout to Railway's
#    one-volume-per-service limit (single volume at /data + symlinks).
# 2. Generates deterministic TLS certs for the actual Railway private hostname.
# 3. Renders ossec.conf with the Railway indexer URL.
# 4. Hands off to the stock s6 entrypoint (/init), which seeds /var/ossec from
#    the image, templates filebeat.yml from env, creates the API user and
#    starts wazuh-control.
set -euo pipefail

: "${INDEXER_URL:?INDEXER_URL is required (https://<indexer-service>.railway.internal:9200)}"
: "${INDEXER_PASSWORD:?INDEXER_PASSWORD is required (reference wazuh-indexer.INDEXER_PASSWORD)}"
: "${API_PASSWORD:?API_PASSWORD is required (reference wazuh-indexer.API_PASSWORD)}"
: "${WAZUH_CA_SEED:?WAZUH_CA_SEED is required (reference wazuh-indexer.WAZUH_CA_SEED)}"
: "${RAILWAY_PRIVATE_DOMAIN:?RAILWAY_PRIVATE_DOMAIN must be set by Railway}"

export INDEXER_USERNAME="${INDEXER_USERNAME:-admin}"
export FILEBEAT_SSL_VERIFICATION_MODE="${FILEBEAT_SSL_VERIFICATION_MODE:-full}"
export SSL_CERTIFICATE_AUTHORITIES="${SSL_CERTIFICATE_AUTHORITIES:-/etc/ssl/root-ca.pem}"
export SSL_CERTIFICATE="${SSL_CERTIFICATE:-/etc/ssl/filebeat.pem}"
export SSL_KEY="${SSL_KEY:-/etc/ssl/filebeat.key}"
export API_USERNAME="${API_USERNAME:-wazuh-wui}"
export AUTO_ENROLLMENT_ENABLED="${AUTO_ENROLLMENT_ENABLED:-true}"

# --- 1. one-volume persistence (Railway: one volume per service) -------------
PERSIST=(
  /var/ossec/api/configuration
  /var/ossec/etc
  /var/ossec/logs
  /var/ossec/queue
  /var/ossec/var/multigroups
  /var/ossec/integrations
  /var/ossec/active-response/bin
  /var/ossec/agentless
  /var/ossec/wodles
  /etc/filebeat
  /var/lib/filebeat
)
for d in "${PERSIST[@]}"; do
  slug="$(printf '%s' "$d" | sed 's|^/||; s|/|_|g')"
  vol="/data/$slug"
  if [ ! -d "$vol" ] || [ -z "$(ls -A "$vol" 2>/dev/null)" ]; then
    mkdir -p "$vol"
    cp -a "$d/." "$vol/" 2>/dev/null || true
  fi
  rm -rf "$d"
  ln -s "$vol" "$d"
done

# --- 2. deterministic TLS material -------------------------------------------
python3 /railway/wazuh_certs.py manager /etc/ssl
# Filebeat expects filebeat.pem/filebeat.key; the generator names leaves by CN.
ln -sf wazuh-manager.pem /etc/ssl/filebeat.pem
ln -sf wazuh-manager.key /etc/ssl/filebeat.key

# --- 3. ossec.conf with the Railway indexer host ------------------------------
sed "s|<host>https://wazuh.indexer:9200</host>|<host>${INDEXER_URL}</host>|g" \
  /railway/ossec.conf.tpl > /var/ossec/etc/ossec.conf
chown root:wazuh /var/ossec/etc/ossec.conf
chmod 640 /var/ossec/etc/ossec.conf

# --- 4. stock entrypoint -------------------------------------------------------
exec /init
