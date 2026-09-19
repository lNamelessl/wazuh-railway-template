#!/usr/bin/env bash
# Wazuh indexer entrypoint for Railway.
# Generates deterministic TLS certs for the actual Railway private hostname,
# renders opensearch.yml + internal_users.yml from deploy-time secrets, then
# hands off to the stock image entrypoint (which drops to uid 1000 itself).
set -euo pipefail

: "${INDEXER_PASSWORD:?INDEXER_PASSWORD is required (per-deploy secret)}"
: "${DASHBOARD_PASSWORD:?DASHBOARD_PASSWORD is required (per-deploy secret)}"
: "${WAZUH_CA_SEED:?WAZUH_CA_SEED is required (per-deploy secret)}"
: "${RAILWAY_PRIVATE_DOMAIN:?RAILWAY_PRIVATE_DOMAIN must be set by Railway}"

export INDEXER_USERNAME="${INDEXER_USERNAME:-admin}"
export OPENSEARCH_JAVA_OPTS="${OPENSEARCH_JAVA_OPTS:--Xms1g -Xmx1g}"

# --- certs -------------------------------------------------------------------
rm -rf /usr/share/wazuh-indexer/certs
mkdir -p /usr/share/wazuh-indexer/certs
python3 /railway/wazuh_certs.py indexer /usr/share/wazuh-indexer/certs

# --- opensearch.yml -----------------------------------------------------------
sed -e "s|__DOMAIN__|${RAILWAY_PRIVATE_DOMAIN}|g" \
  /railway/opensearch.yml.tpl > /usr/share/wazuh-indexer/opensearch.yml

# --- internal users (bcrypt of the generated passwords) -----------------------
INDEXER_PASSWORD="${INDEXER_PASSWORD}" DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD}" \
  python3 /railway/gen_internal_users.py \
  > /usr/share/wazuh-indexer/opensearch-security/internal_users.yml

# --- ownership/permissions for the indexer user (uid 1000) --------------------
chown -R 1000:0 /usr/share/wazuh-indexer/certs /usr/share/wazuh-indexer/logs \
  /var/lib/wazuh-indexer /var/log/wazuh-indexer /run/wazuh-indexer 2>/dev/null || true
chown 1000:0 /usr/share/wazuh-indexer/opensearch.yml \
  /usr/share/wazuh-indexer/opensearch-security/internal_users.yml
chmod 700 /usr/share/wazuh-indexer/certs
chmod 400 /usr/share/wazuh-indexer/certs/*
chmod 600 /usr/share/wazuh-indexer/opensearch.yml
chmod 640 /usr/share/wazuh-indexer/opensearch-security/internal_users.yml

# --- stock entrypoint (drops to uid 1000 via chroot --userspec) ---------------
exec /entrypoint.sh
