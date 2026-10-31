#!/usr/bin/env python3
"""Provision isolated financial roles and apply the versioned RLS fence atomically.

The source env file contains the existing bootstrap administrator credential.
Credentials and reversible ownership metadata are written only to a private file.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit, urlunsplit, quote
import psycopg
from psycopg import sql

APP_SCHEMAS = ['core','market','asset_details','analytics','wealth','social','system','dw',
    'canonical','raw','ingestion','graph','billing','reconciliation','suitability','public_dw','cms','audit']


def provision(args):
    values = {}
    for line in Path(args.admin_env).read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            key,value=line.split('=',1);values[key]=value.strip().strip('\"\'')
    admin_url=values['DATABASE_URL'].replace('postgresql+asyncpg://','postgresql://').replace('ssl=require','sslmode=require')
    parts=urlsplit(admin_url)
    if parts.path == '/fin_cms':
        raise RuntimeError('Financial roles cannot target the CMS database')
    direct_host=parts.hostname.replace('-pooler.', '.')
    admin_direct=urlunsplit((parts.scheme,parts.netloc.replace(parts.hostname,direct_host),parts.path,parts.query,''))
    output=Path(args.output)
    if output.exists():cfg=json.loads(output.read_text())
    else:
        cfg={'passwords':{role:secrets.token_urlsafe(48) for role in ['fin_api_rw','fin_ingestion_rw','fin_migration_owner','fin_readonly_public']}}
        output.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        with os.fdopen(os.open(output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600),'w') as file:json.dump(cfg,file,indent=2)
    migration=Path(args.migration)
    version='18_runtime_security/'+migration.name
    checksum=hashlib.sha256(migration.read_bytes()).hexdigest()
    with psycopg.connect(admin_direct,connect_timeout=25) as conn:
        conn.execute("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='120s'")
        conn.execute('SELECT pg_advisory_xact_lock(742198273)')
        applied=conn.execute('SELECT checksum FROM system.schema_migrations WHERE version=%s',(version,)).fetchone()
        if applied and applied[0] != checksum:raise RuntimeError('Security migration checksum drift')
        if 'ownership_before' not in cfg:
            cfg['ownership_before']=conn.execute("SELECT n.nspname,c.relname,pg_get_userbyid(c.relowner),c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=ANY(%s) AND c.relkind IN ('r','p','v','m','S')",(APP_SCHEMAS,)).fetchall()
        for role,password in cfg['passwords'].items():
            exists=conn.execute('SELECT rolcanlogin,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=%s',(role,)).fetchone()
            if exists and (exists[1] or exists[2]):raise RuntimeError('Unexpected privileged runtime role')
            if not exists:
                conn.execute(sql.SQL('CREATE ROLE {} LOGIN PASSWORD {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS').format(sql.Identifier(role),sql.Literal(password)))
            elif not exists[0]:
                conn.execute(sql.SQL('ALTER ROLE {} LOGIN PASSWORD {}').format(sql.Identifier(role),sql.Literal(password)))
        # Membership goes to the bootstrap administrator, never to runtime roles.
        conn.execute(sql.SQL('GRANT fin_migration_owner TO {} WITH SET TRUE, INHERIT TRUE').format(sql.Identifier(conn.info.user)))
        if not applied:
            conn.execute(migration.read_text())
            for schema in APP_SCHEMAS:
                if not conn.execute('SELECT 1 FROM pg_namespace WHERE nspname=%s',(schema,)).fetchone():continue
                conn.execute(sql.SQL('ALTER SCHEMA {} OWNER TO fin_migration_owner').format(sql.Identifier(schema)))
                objects=conn.execute("SELECT c.relname,c.relkind,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=%s AND c.relkind IN ('r','p','v','m','S') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=c.oid AND d.deptype='e') ORDER BY CASE WHEN c.relkind='S' THEN 1 ELSE 0 END",(schema,)).fetchall()
                for name,kind,rls in objects:
                    command={'v':'VIEW','m':'MATERIALIZED VIEW','S':'SEQUENCE'}.get(kind,'TABLE')
                    try:
                        with conn.transaction():
                            conn.execute(sql.SQL('ALTER '+command+' {}.{} OWNER TO fin_migration_owner').format(sql.Identifier(schema),sql.Identifier(name)))
                    except (psycopg.errors.InsufficientPrivilege, psycopg.errors.FeatureNotSupported, psycopg.errors.ObjectNotInPrerequisiteState):
                        # Managed Timescale chunks and their dependent sequences retain
                        # provider ownership. No runtime role receives ownership.
                        cfg.setdefault('provider_ownership_retained', []).append([schema,name])
                    if rls:
                        conn.execute(sql.SQL('DROP POLICY IF EXISTS fin_migrations_owner ON {}.{}').format(sql.Identifier(schema),sql.Identifier(name)))
                        conn.execute(sql.SQL('CREATE POLICY fin_migrations_owner ON {}.{} FOR ALL TO fin_migration_owner USING (true) WITH CHECK (true)').format(sql.Identifier(schema),sql.Identifier(name)))
                functions=conn.execute("SELECT p.proname,pg_get_function_identity_arguments(p.oid),p.prokind FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=%s AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=p.oid AND d.deptype='e')",(schema,)).fetchall()
                for name,arguments,kind in functions:
                    command='PROCEDURE' if kind=='p' else 'FUNCTION'
                    conn.execute(sql.SQL('ALTER '+command+' {}.{} ('+arguments+') OWNER TO fin_migration_owner').format(sql.Identifier(schema),sql.Identifier(name)))
                types=conn.execute("SELECT t.typname FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname=%s AND t.typtype IN ('e','d') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.objid=t.oid AND d.deptype='e')",(schema,)).fetchall()
                for (name,) in types:conn.execute(sql.SQL('ALTER TYPE {}.{} OWNER TO fin_migration_owner').format(sql.Identifier(schema),sql.Identifier(name)))
                if schema in ['core','wealth','system','billing','audit']:
                    conn.execute(sql.SQL('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA {} FROM PUBLIC').format(sql.Identifier(schema)))
            conn.execute('INSERT INTO system.schema_migrations(version,checksum) VALUES(%s,%s)',(version,checksum))
        if conn.execute("SELECT pg_has_role('fin_api_rw','fin_migration_owner','MEMBER') OR pg_has_role('fin_ingestion_rw','fin_migration_owner','MEMBER')").fetchone()[0]:raise RuntimeError('Runtime inherited migration ownership')
    cfg['urls']={}
    for role,password in cfg['passwords'].items():
        host=direct_host if role=='fin_migration_owner' else parts.hostname
        netloc=f'{role}:{quote(password,safe="")}@{host}'+(f':{parts.port}' if parts.port else '')
        cfg['urls'][role]=urlunsplit(('postgresql',netloc,parts.path,'sslmode=require' if parts.hostname not in ('localhost','127.0.0.1') else '', ''))
    cfg['migration']={'version':version,'checksum':checksum,'applied':True}
    output.write_text(json.dumps(cfg,indent=2));os.chmod(output,0o600)
    print('Financial roles, restricted grants, tenant fences and migration ownership applied atomically.')
    print('Runtime roles have no bypass or inherited migration ownership. Credentials saved privately.')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--admin-env',required=True);parser.add_argument('--output',required=True);parser.add_argument('--migration',required=True)
    try:provision(parser.parse_args())
    except Exception as error:
        print('Financial security bootstrap failed:',type(error).__name__)
        if getattr(error, 'diag', None) and error.diag.message_primary:
            print(error.diag.message_primary)
        # Do not log SQL statements: role provisioning statements contain passwords.
        raise SystemExit(1)
