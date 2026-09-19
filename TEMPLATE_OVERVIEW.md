# Wazuh SIEM — security monitoring in one click

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/hsBvLL)

Wazuh 4.14.7 all-in-one: **manager** (agent ingestion + rules + API), **indexer**
(OpenSearch-based, 1 GB JVM heap), and **dashboard** — with TLS between all components
generated at deploy time for Railway's private hostnames, and zero demo credentials.

> **Resource honesty:** Wazuh officially recommends ~8 GB RAM. Actual concurrent usage is
> **4–6 GB** (indexer JVM 1 GB heap + manager + dashboard) — budget roughly **$25–50/month**
> on Railway usage-based billing. The first boot takes 3–5 minutes (indexer JVM boot is slow;
> the dashboard crash-loops until the indexer is ready, then stabilizes).

## What you get

| Service | Image (pinned) | Networking | Volume |
|---|---|---|---|
| `wazuh-manager` | `wazuh/wazuh-manager:4.14.7` | TCP proxies **1514** (agent reporting) + **1515** (agent enrolment); API 55000 private-only | `/var/ossec/data` |
| `wazuh-indexer` | `wazuh/wazuh-indexer:4.14.7` | private `wazuh-indexer.railway.internal:9200` (TLS) | `/var/lib/wazuh-indexer` |
| `wazuh-dashboard` | `wazuh/wazuh-dashboard:4.14.7` | public HTTPS domain → 5601 | — |

- **Zero deploy-form prompts**: all credentials are `${{secret()}}` expressions generated
  per deploy — `INDEXER_PASSWORD` (dashboard/API login user **admin**), `DASHBOARD_PASSWORD`
  (kibanaserver service account), `API_PASSWORD` (wazuh-wui API user), `WAZUH_CA_SEED`
  (TLS root derivation). No upstream demo value (admin/SecretPassword etc.) exists anywhere.
- **Deploy-time TLS**: each service derives the same root CA deterministically from
  `WAZUH_CA_SEED` and issues itself a certificate for its actual
  `<service>.railway.internal` hostname — no init container, no shared volumes needed,
  byte-stable across restarts.
- One Railway volume per service (Railway limit) with Wazuh's permanent-data directories
  symlinked into it; alerts, agent keys and inventory state persist across redeploys.

## After deploying

1. Open the **wazuh-dashboard** public domain and log in as user **admin** with the
   `INDEXER_PASSWORD` value (Variables tab of `wazuh-indexer` — the other services
   reference the same value).
2. Give the stack 3–5 minutes on first boot before judging health.
3. Enrol an agent (see below) and watch it go **Active** in the dashboard within a minute.

## Enrolling agents

Railway has no UDP and no raw TCP ports, so the manager's agent ports are exposed as two
**TCP proxies** (visible in the `wazuh-manager` service → Settings → Networking): one maps
to **1514** (reporting), one to **1515** (enrolment). Each proxy has its own
`*.proxy.rlwy.net:port` pair.

Linux agent, package install: point `<address>` at the **1514 proxy host**, `<port>` at
its public port, and run `agent-auth` against the **1515 proxy host:port** (see
[Wazuh agent docs](https://documentation.wazuh.com/current/user-manual/agents/registering-agents.html)).

Docker (the upstream `wazuh/wazuh-agent` image has a config bug at 4.14.7 — empty
`<address>` fields — so use the tiny wrapper in this repo's `agent/` directory):

```bash
git clone https://github.com/lNamelessl/wazuh-railway-template && cd wazuh-railway-template
docker build -t wazuh-agent-railway ./agent

docker run -d --name wazuh-agent \
  -e WAZUH_MANAGER_SERVER='<1514-proxy-host>' \
  -e WAZUH_MANAGER_PORT='<1514-proxy-port>' \
  -e WAZUH_REGISTRATION_SERVER='<1515-proxy-host>' \
  -e WAZUH_REGISTRATION_PORT='<1515-proxy-port>' \
  -e WAZUH_AGENT_NAME='my-host' \
  wazuh-agent-railway
```

## Credential rotation

- `API_PASSWORD` rotates cleanly: the manager re-applies it at every boot.
- `INDEXER_PASSWORD` / `DASHBOARD_PASSWORD` are hashed into the indexer's security index on
  first boot only — changing them later requires wiping the indexer volume.
- Re-keying the whole TLS mesh = changing `WAZUH_CA_SEED` (then wipe the indexer volume;
  the security index stores certificate DNs).

# Deploy and Host

## About Hosting

This template provisions three services on Railway: the Wazuh manager (agent
ingestion/enrolment over TCP proxies 1514/1515, API on private port 55000), the Wazuh
indexer (OpenSearch fork with 1 GB JVM heap, TLS, private networking only), and the Wazuh
dashboard (public HTTPS domain, login with the deploy-generated `admin` password). TLS
certificates for all internal hops are generated at deploy time from the shared
`WAZUH_CA_SEED` secret, matched to Railway's `*.railway.internal` private hostnames.
Persistent state lives in one volume per service (Railway's limit) — alerts, enrolled agent
keys and inventory indices survive restarts. Expect 4–6 GB RAM in actual use (~$25–50/mo);
the first boot takes 3–5 minutes.

## Why Deploy

Wazuh normally wants a VM with 8+ GB RAM and manual certificate generation for every
hostname — the most fiddly part of the install. This template does the cert generation
automatically at deploy time for Railway's actual private DNS names, wires the manager,
indexer and dashboard together over mutual TLS, and generates every credential per deploy
so no demo password ever ships. You get a working SIEM with a public dashboard URL and
publicly reachable agent ports without owning any infrastructure.

## Common Use Cases

- Security monitoring for small teams: log collection, detection rules, file integrity
  monitoring and vulnerability detection out of the box.
- A SIEM lab/learning environment for Wazuh rules, dashboards and the detection-as-code
  workflow.
- Central log analysis endpoint for remote agents: laptops, servers and containers enrol
  over the public TCP proxies and stream events into `wazuh-alerts-*`.
- Compliance starting points (PCI DSS, GDPR, HIPAA, NIST 800-53 dashboards ship with
  Wazuh).

## Dependencies for

### Deployment Dependencies

- A Railway workspace with enough headroom for ~4–6 GB RAM across three services.
- No external services required: the indexer replaces any managed database, certificates
  are generated in-cluster, and vulnerability-detection feeds are downloaded from Wazuh's
  CDN at runtime.
- Outbound internet for image pulls and CVE feed updates; TCP proxies for external agents
  (Railway has no UDP, so syslog 514/udp is not available — use agents).
