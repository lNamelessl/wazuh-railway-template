# Wazuh manager with Railway adaptations (deterministic certs + one-volume persistence)
FROM wazuh/wazuh-manager:4.12.0

RUN dnf install -y python3 python3-pip && \
    python3 -m pip install --no-cache-dir cryptography && \
    dnf clean all

COPY railway/ /railway/
RUN chmod +x /railway/start.sh

ENTRYPOINT ["/railway/start.sh"]
