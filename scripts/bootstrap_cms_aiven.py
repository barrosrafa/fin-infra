#!/usr/bin/env python3
"""Additive CMS isolation. Credentials go to a private file, never stdout.

AIVEN_ADMIN_URL is bootstrap-only. Existing roles/databases are refused to avoid
silently taking ownership or rotating a credential used by another deployment.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
from urllib.parse import quote, urlsplit, urlunsplit

import psycopg
from psycopg import sql


def bootstrap(admin_url, output):
    output = Path(output)
    if output.exists():
        raise RuntimeError("Credential output already exists; no rotation performed")
    role_passwords = {name: secrets.token_urlsafe(48) for name in ("cms_migration_owner", "cms_directus_rw")}
    parts = urlsplit(admin_url)
    def url(role, password):
        return urlunsplit(("postgresql", f"{role}:{quote(password, safe='')}@{parts.hostname}:{parts.port or 5432}", "/fin_cms", "sslmode=require", ""))
    config = {
        "CMS_DATABASE_URL": url("cms_directus_rw", role_passwords["cms_directus_rw"]),
        "CMS_MIGRATION_DATABASE_URL": url("cms_migration_owner", role_passwords["cms_migration_owner"]),
        "DIRECTUS_SECRET": secrets.token_urlsafe(64),
    }
    # Persist before any remote mutation so a partial provision never loses passwords.
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as file:
        json.dump(config, file, indent=2)
    with psycopg.connect(admin_url, autocommit=True, connect_timeout=12) as conn:
        if conn.execute("SELECT 1 FROM pg_database WHERE datname='fin_cms'").fetchone():
            raise RuntimeError("fin_cms exists; inspect it before any change")
        if conn.execute("SELECT 1 FROM pg_roles WHERE rolname = ANY(%s)", (list(role_passwords),)).fetchone():
            raise RuntimeError("CMS roles already exist; inspect before any change")
        with conn.transaction():
            for role, password in role_passwords.items():
                conn.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS").format(sql.Identifier(role), sql.Literal(password)))
            conn.execute(sql.SQL("GRANT cms_migration_owner TO {} WITH SET TRUE").format(sql.Identifier(conn.info.user)))
        conn.execute("CREATE DATABASE fin_cms OWNER cms_migration_owner")
        conn.execute("REVOKE ALL ON DATABASE fin_cms FROM PUBLIC")
        conn.execute("GRANT CONNECT ON DATABASE fin_cms TO cms_directus_rw")
    with psycopg.connect(config["CMS_MIGRATION_DATABASE_URL"], connect_timeout=12) as conn:
        conn.execute("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
        conn.execute("CREATE SCHEMA cms AUTHORIZATION cms_migration_owner")
        conn.execute("GRANT USAGE ON SCHEMA cms TO cms_directus_rw")
        conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA cms GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO cms_directus_rw")
        conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA cms GRANT USAGE,SELECT ON SEQUENCES TO cms_directus_rw")
    # An actual runtime connection proves login and denial of schema DDL.
    with psycopg.connect(config["CMS_DATABASE_URL"], connect_timeout=12) as conn:
        flags = conn.execute("SELECT rolcreatedb,rolcreaterole,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user").fetchone()
        if any(flags):
            raise RuntimeError("Runtime role has forbidden administrative flags")
        try:
            with conn.transaction():
                conn.execute("CREATE TABLE cms._forbidden_test(id integer)")
        except psycopg.errors.InsufficientPrivilege:
            pass
        else:
            raise RuntimeError("Runtime unexpectedly allowed DDL")
    print("CMS database and isolated roles created; runtime login and DDL denial verified.")
    print("Credentials saved privately; no administrative URL was persisted.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        bootstrap(os.environ["AIVEN_ADMIN_URL"], args.output)
    except Exception as error:
        # Database exceptions can contain statements with passwords: do not print them.
        print(f"Bootstrap failed ({type(error).__name__}); inspect remote state before retrying.")
        raise SystemExit(1)
