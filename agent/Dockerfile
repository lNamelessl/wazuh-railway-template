# Wazuh agent with a fix for the upstream 4.14.7 image bug (empty
# <address>/<manager_address> in ossec.conf breaks env-based enrollment).
FROM wazuh/wazuh-agent:4.14.7

COPY railway/start.sh /railway/start.sh
RUN chmod +x /railway/start.sh

ENTRYPOINT ["/railway/start.sh"]
