#!/usr/bin/env bash
# Wazuh agent wrapper for Railway verification (and for users who want a
# containerized agent). The upstream 4.14.7 agent image ships its ossec.conf
# with EMPTY <address>/<manager_address> fields (its env-var seds expect
# CHANGE_* placeholders that the RPM build already consumed), so enrollment
# fails with "Invalid server address found: ''". Fill them from env here.
set -euo pipefail

CONF=/var/ossec/etc/ossec.conf

if [ -n "${WAZUH_MANAGER_SERVER:-}" ]; then
  sed -i "s|<address></address>|<address>${WAZUH_MANAGER_SERVER}</address>|g" "$CONF"
fi
if [ -n "${WAZUH_REGISTRATION_SERVER:-}" ]; then
  sed -i "s|<manager_address></manager_address>|<manager_address>${WAZUH_REGISTRATION_SERVER}</manager_address>|g" "$CONF"
fi
sed -i "s|<port>CHANGE_MANAGER_PORT</port>|<port>${WAZUH_MANAGER_PORT:-1514}</port>|g" "$CONF"
sed -i "s|<port>CHANGE_ENROLL_PORT</port>|<port>${WAZUH_REGISTRATION_PORT:-1515}</port>|g" "$CONF"

exec /init
