# Wazuh manager with Railway adaptations (deterministic certs + one-volume persistence)
FROM wazuh/wazuh-manager:4.12.0

RUN dnf install -y python3 python3-pip && \
    python3 -m pip install --no-cache-dir cryptography && \
    dnf clean all

# 0-wazuh-init uses `find <dir> -mindepth 1` to decide whether a permanent-data
# dir is already populated. find(1) does not follow symlinks given as arguments,
# so with our /data volume symlinks it would re-seed from data_tmp on EVERY
# boot — resetting ossec.conf (stock copy has CRLF endings that Wazuh's XML
# parser rejects) and wiping client.keys (enrolled agent keys). Make it follow
# symlinks so populated volume dirs are detected correctly.
RUN sed -i 's|find ${permanent_dir} -mindepth 1|find -L ${permanent_dir} -mindepth 1|' \
    /etc/cont-init.d/0-wazuh-init

COPY railway/ /railway/
RUN chmod +x /railway/start.sh

ENTRYPOINT ["/railway/start.sh"]
