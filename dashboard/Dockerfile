# Wazuh dashboard with Railway adaptations (deterministic certs, edge-terminated TLS)
FROM wazuh/wazuh-dashboard:4.12.0

USER root

RUN dnf install -y python3 python3-pip && \
    python3 -m pip install --no-cache-dir cryptography && \
    dnf clean all

COPY railway/ /railway/
RUN chmod +x /railway/start.sh

ENTRYPOINT ["/railway/start.sh"]
