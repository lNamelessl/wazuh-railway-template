# Wazuh indexer with Railway adaptations (deterministic certs + secret-driven security init)
FROM wazuh/wazuh-indexer:4.14.7

USER root

RUN dnf install -y python3 python3-pip && \
    python3 -m pip install --no-cache-dir cryptography bcrypt && \
    dnf clean all

COPY railway/ /railway/
RUN chmod +x /railway/start.sh

ENTRYPOINT ["/railway/start.sh"]
