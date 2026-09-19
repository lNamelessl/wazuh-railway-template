#!/usr/bin/env python3
"""Render internal_users.yml with bcrypt hashes of the deploy-time secrets.

admin    -> INDEXER_PASSWORD   (dashboard + API login user)
kibanaserver -> DASHBOARD_PASSWORD (dashboard -> indexer service account)

The upstream demo file ships four extra unused users with publicly known
passwords (kibanaro, logstash, readall, snapshotrestore); they are dropped so
no known demo credential exists in the deployment. The security index is
initialized from this file on first boot (allow_default_init_securityindex).
"""
import os

import bcrypt


def bcrypt_hash(password: str) -> str:
    return bcrypt.hashpw(
        password.encode(), bcrypt.gensalt(rounds=12, prefix=b"2a")
    ).decode()


def main() -> None:
    admin_pw = os.environ["INDEXER_PASSWORD"]
    kibana_pw = os.environ["DASHBOARD_PASSWORD"]
    print(
        f"""---
# Generated at deploy time by the Railway template. Hashes are bcrypt of the
# per-deploy INDEXER_PASSWORD / DASHBOARD_PASSWORD secrets. Changing the
# secrets later requires wiping the indexer volume (security index seeding).
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "{bcrypt_hash(admin_pw)}"
  reserved: true
  backend_roles:
  - "admin"
  description: "Wazuh admin user (password from deploy-time secret)"

kibanaserver:
  hash: "{bcrypt_hash(kibana_pw)}"
  reserved: true
  description: "Wazuh dashboard service account"
""",
        end="",
    )


if __name__ == "__main__":
    main()
