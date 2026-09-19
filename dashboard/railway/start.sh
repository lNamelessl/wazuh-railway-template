#!/usr/bin/env bash
# Wazuh dashboard entrypoint for Railway.
# Generates the deterministic CA copy (to verify the indexer over TLS), renders
# opensearch_dashboards.yml with the Railway indexer URL, then hands off to the
# stock image entrypoint (keystore from DASHBOARD_* env, wazuh.yml API host from
# WAZUH_API_URL/API_USERNAME/API_PASSWORD, starts opensearch-dashboards).
# Public TLS is terminated by Railway's edge; server.ssl stays off internally.
set -euo pipefail

: "${INDEXER_URL:?INDEXER_URL is required (https://<indexer-service>.railway.internal:9200)}"
: "${DASHBOARD_PASSWORD:?DASHBOARD_PASSWORD is required (reference wazuh-indexer.DASHBOARD_PASSWORD)}"
: "${API_PASSWORD:?API_PASSWORD is required (reference wazuh-indexer.API_PASSWORD)}"
: "${WAZUH_CA_SEED:?WAZUH_CA_SEED is required (reference wazuh-indexer.WAZUH_CA_SEED)}"

export INDEXER_USERNAME="${INDEXER_USERNAME:-admin}"
export DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-kibanaserver}"
export API_USERNAME="${API_USERNAME:-wazuh-wui}"
export API_PORT="${API_PORT:-55000}"
export WAZUH_API_URL="${WAZUH_API_URL:-https://wazuh-manager.railway.internal}"

# --- deterministic TLS material (root CA is what matters here) ----------------
mkdir -p /usr/share/wazuh-dashboard/certs
python3 /railway/wazuh_certs.py dashboard /usr/share/wazuh-dashboard/certs

# --- dashboards config ----------------------------------------------------------
sed -e "s|__INDEXER_URL__|${INDEXER_URL}|g" \
  /railway/opensearch_dashboards.yml.tpl \
  > /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml

# --- ownership for the dashboard user (uid 1000) --------------------------------
chown -R 1000:0 /usr/share/wazuh-dashboard/certs /usr/share/wazuh-dashboard/config \
  /usr/share/wazuh-dashboard/data 2>/dev/null || true
chmod 700 /usr/share/wazuh-dashboard/certs
chmod 400 /usr/share/wazuh-dashboard/certs/*

# --- stock entrypoint as uid 1000 ------------------------------------------------
exec chroot --userspec=1000:0 / /entrypoint.sh
