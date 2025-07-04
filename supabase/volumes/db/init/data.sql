CREATE if not exists schema n8n

GRANT ALL PRIVILEGES ON DATABASE "postgres" to n8n;

GRANT ALL PRIVILEGES ON schema "n8n" to n8n;