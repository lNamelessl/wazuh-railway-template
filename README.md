# Wazuh all-in-one — Railway Template

[Wazuh](https://wazuh.com) — open-source security monitoring (SIEM/XDR): manager (agent
ingestion + rules), OpenSearch-based indexer, and dashboard — packaged as a one-click
Railway template with **deploy-time TLS certificate generation matched to Railway private
DNS** and **zero demo credentials**.

> **Resource honesty:** Wazuh officially wants ~8 GB RAM (indexer JVM alone is pinned at 1 GB).
> Expect **4–6 GB** actual concurrent usage — roughly **$25–50/mo** on Railway usage-based billing.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/wazuh-template)

## Services

| Service | Image (pinned) | Networking | Volume |
|---|---|---|---|
| `wazuh-manager` | `wazuh/wazuh-manager:4.12.0` | TCP proxies **1514** (agent events) + **1515** (agent enrolment); API **55000** private-only | `/data` (ossec + filebeat state) |
| `wazuh-indexer` | `wazuh/wazuh-indexer:4.12.0` | private-only `wazuh-indexer.railway.internal:9200` (TLS) | `/var/lib/wazuh-indexer` |
| `wazuh-dashboard` | `wazuh/wazuh-dashboard:4.12.0` | public domain (Railway TLS) → 5601 | — |

## How TLS works on Railway

Railway private DNS (`*.railway.internal`) never matches Wazuh's compose hostnames, and
Railway services cannot share volumes, so the upstream cert-generator one-shot container
cannot be used. Instead every service runs a small init step (`<svc>/railway/wazuh_certs.py`)
that **derives the same root CA deterministically from the shared `WAZUH_CA_SEED` secret**
and issues each service a leaf certificate for its actual `RAILWAY_PRIVATE_DOMAIN`
(CN/SAN `CN=<name>,OU=Wazuh,O=Wazuh,L=California,C=US`). Keys are a pure function of
`(seed, role, hostname)` — so first boot, restarts and redeploys all regenerate identical,
mutually-trusting material with zero coordination. See [DESIGN.md](DESIGN.md).

## Credentials (all auto-generated per deploy)

| Secret | Used as | Referenced by |
|---|---|---|
| `WAZUH_CA_SEED` | TLS CA derivation seed | all 3 services |
| `INDEXER_PASSWORD` | indexer/dashboard **login user `admin`**, filebeat + manager indexer client | manager, indexer, dashboard |
| `DASHBOARD_PASSWORD` | `kibanaserver` service account (dashboard → indexer) | indexer, dashboard |
| `API_PASSWORD` | Wazuh API user `wazuh-wui` | manager, dashboard |

All are `${{secret(...)}}` expressions declared once on `wazuh-indexer` and referenced
cross-service — the deploy form has **zero prompts** and no `SecretPassword`-style demo value
exists anywhere. Unused upstream demo users (kibanaro/logstash/readall/snapshotrestore) are
not provisioned.

**Rotation caveat:** indexer user hashes are seeded into the security index on first boot.
Changing `INDEXER_PASSWORD`/`DASHBOARD_PASSWORD` later requires wiping the indexer volume.
`API_PASSWORD` rotates cleanly (re-applied by the manager at every boot).

## Enrolling agents

Agents connect to the manager over the **TCP proxies** (Railway has no UDP — syslog 514/udp
is not available):

1. Open the `wazuh-manager` service → Settings → Networking: note the two TCP proxy domains
   (`*.proxy.rlwy.net:port`) and which maps to 1515 (enrolment) vs 1514 (reporting).
2. On your agent host (Linux example):

   ```bash
   WAZUH_MANAGER='<1514-proxy-domain>' \
   WAZUH_MANAGER_PORT='<1514-proxy-port>' \
   WAZUH_REGISTRATION_SERVER='<1515-proxy-domain>' \
   WAZUH_REGISTRATION_PORT='<1515-proxy-port>' \
   WAZUH_AGENT_NAME='my-laptop' \
   docker run -d --name wazuh-agent wazuh/wazuh-agent:4.12.0
   ```

   Package installs: `agent-auth`/`manager-address` config per
   [Wazuh docs](https://documentation.wazuh.com/current/user-manual/agents/registering-agents.html)
   using the proxy host/port pair from step 1.
3. The agent appears in the dashboard (Agents) within seconds; events land in
   `wazuh-alerts-*`.

## Notes and troubleshooting

- **Slow first boot:** the indexer JVM (1 GB heap) needs 1–3 minutes; the dashboard
  crash-loops until the indexer is up and then stabilizes — this is expected.
- **Memory:** if the indexer is OOM-killed, raise JVM via `OPENSEARCH_JAVA_OPTS` (e.g.
  `-Xms2g -Xmx2g`) and keep total usage within your plan.
- **Certs:** never hand-edit `/etc/ssl` or `.../certs` — they regenerate deterministically
  each boot. To re-key the mesh, change `WAZUH_CA_SEED` (and wipe the indexer volume — the
  security index stores TLS-DN-bound config).
- **Dashboard won't load:** check `wazuh-indexer` logs first (security init happens on the
  first boot only), then the dashboard logs for indexer-auth errors.
- **Agents stuck "Never connected":** confirm you used the **1514 proxy** for reporting and
  the **1515 proxy** for enrolment (they are different public host:port pairs).
- **No UDP:** syslog ingestion on 514/udp is impossible on Railway; use agents or
  syslog-over-TCP relays.
