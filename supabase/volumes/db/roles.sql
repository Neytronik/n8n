-- NOTE: change to your own passwords for production environments
\set pgpass `echo "$POSTGRES_PASSWORD"`

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n') THEN
        CREATE ROLE n8n WITH LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS;
        GRANT ALL PRIVILEGES ON DATABASE postgres TO n8n;
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS n8n;
GRANT ALL PRIVILEGES ON DATABASE "postgres" to n8n;
GRANT ALL PRIVILEGES ON schema "n8n" to n8n;

ALTER USER authenticator WITH PASSWORD :'pgpass';
ALTER USER pgbouncer WITH PASSWORD :'pgpass';
ALTER USER supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_storage_admin WITH PASSWORD :'pgpass';
ALTER USER supabase_admin WITH PASSWORD :'pgpass';
ALTER USER n8n WITH PASSWORD :'pgpass';
