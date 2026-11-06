#!/usr/bin/env python3
"""Apply production-oriented Matrix Synapse settings after official config generation."""
import os
import yaml

path = "/data/homeserver.yaml"
with open(path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

server_name = os.environ["SERVER_NAME"]
db_password = os.environ["POSTGRES_PASSWORD"]
registration_secret = os.environ["SYNAPSE_REGISTRATION_SHARED_SECRET"]

cfg["server_name"] = server_name
cfg["public_baseurl"] = f"https://{server_name}/"
cfg["report_stats"] = False
cfg["enable_registration"] = False
cfg["enable_registration_without_verification"] = False
cfg["registration_shared_secret"] = registration_secret
cfg["database"] = {
    "name": "psycopg2",
    "args": {
        "user": "synapse",
        "password": db_password,
        "database": "synapse",
        "host": "db",
        "port": 5432,
        "cp_min": 5,
        "cp_max": 10,
    },
}
for listener in cfg.get("listeners", []):
    if listener.get("port") == 8008:
        listener["bind_addresses"] = ["0.0.0.0"]
        listener["resources"] = [{"names": ["client"], "compress": True}]
# This private beta is not federated: do not expose 8448; only Caddy's 443 is public.
cfg["trusted_key_servers"] = []
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(cfg, f, sort_keys=False, allow_unicode=True)
