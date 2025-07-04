#!/bin/bash

# Проверка зависимостей
if ! command -v git &> /dev/null; then
    echo "Ошибка: Git не установлен. Установите git и повторите попытку."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "Ошибка: Docker не установлен. Установите docker и повторите попытку."
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo "Ошибка: OpenSSL не установлен. Установите openssl и повторите попытку."
    exit 1
fi

if ! command -v certbot &> /dev/null; then
    echo "Ошибка: certbot не установлен. Установите certbot и повторите попытку."
    exit 1
fi

# Генерация JWT токенов
generate_jwt() {
    local role=$1
    local secret=$2
    local header=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 | tr -d '=' | tr '+/' '-_')
    local payload=$(echo -n "{\"role\":\"$role\",\"iss\":\"supabase\",\"iat\":1751403600,\"exp\":1909170000}" | base64 | tr -d '=' | tr '+/' '-_')
    local signature=$(echo -n "$header.$payload" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | tr -d '=' | tr '+/' '-_')
    echo "$header.$payload.$signature"
}

# Генерация секретов
JWT_SECRET=$(openssl rand -hex 20)
POSTGRES_PASSWORD=$(openssl rand -hex 32)
DASHBOARD_PASSWORD=$(openssl rand -hex 16)
POOLER_TENANT_ID="tenant_$(openssl rand -hex 8)"
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')
VAULT_ENC_KEY=$(openssl rand -base64 24 | tr -d '\n')
LOGFLARE_PUBLIC_KEY="lf_pub_$(openssl rand -hex 12)"
LOGFLARE_PRIVATE_KEY="lf_priv_$(openssl rand -hex 24)"

# Генерация ключей
ANON_KEY=$(generate_jwt "anon" "$JWT_SECRET")
SERVICE_ROLE_KEY=$(generate_jwt "service_role" "$JWT_SECRET")

cd supabase

# Обновление .env файла supabase
envsubst <<EOF > .env
############
# Secrets
############

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY


############
# Database
############

POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432


############
# Supavisor
############

POOLER_PROXY_PORT_TRANSACTION=6543
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=$POOLER_TENANT_ID
POOLER_DB_POOL_SIZE=5


############
# API Proxy
############

KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443


############
# API
############

PGRST_DB_SCHEMAS=public,storage,graphql_public


############
# Auth
############

## General
SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:8000

## Mailer Config
MAILER_URLPATHS_CONFIRMATION="/auth/v1/verify"
MAILER_URLPATHS_INVITE="/auth/v1/verify"
MAILER_URLPATHS_RECOVERY="/auth/v1/verify"
MAILER_URLPATHS_EMAIL_CHANGE="/auth/v1/verify"

## Email auth
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=supabase-mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=fake_sender
ENABLE_ANONYMOUS_USERS=false

## Phone auth
ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true


############
# Studio
############

STUDIO_DEFAULT_ORGANIZATION=Default Organization
STUDIO_DEFAULT_PROJECT=Default Project

STUDIO_PORT=3000
SUPABASE_PUBLIC_URL=http://localhost:8000

IMGPROXY_ENABLE_WEBP_DETECTION=true

OPENAI_API_KEY=


############
# Functions
############
FUNCTIONS_VERIFY_JWT=false


############
# Logs
############

LOGFLARE_PUBLIC_ACCESS_TOKEN=$LOGFLARE_PUBLIC_KEY
LOGFLARE_PRIVATE_ACCESS_TOKEN=$LOGFLARE_PRIVATE_KEY

DOCKER_SOCKET_LOCATION=/var/run/docker.sock

GOOGLE_PROJECT_ID=GOOGLE_PROJECT_ID
GOOGLE_PROJECT_NUMBER=GOOGLE_PROJECT_NUMBER
EOF

# Создание external сети
docker network create shared_gateway

# Запуск сервисов
docker compose pull -f docker-compose-local.yml
docker compose up -f docker-compose-local.yml -d

echo "===================================================="
echo "Развертывание Supabase завершено!"
echo "===================================================="


echo "Начинаем развертывание n8n"
N8N_PASSWORD=$(openssl rand -hex 16)
cd ../n8n-project

# Обновление .env файла n8n
envsubst <<EOF > .env
# N8N_HOST=n8n.example.ru
N8N_HOST=localhost
# n8n auth
N8N_BASIC_AUTH_USER=n8nadmin
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
GENERIC_TIMEZONE=Europe/Moscow
# database
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
DB_POSTGRESDB_USER=n8n.$POOLER_TENANT_ID
DB_POSTGRESDB_HOST=db
DB_POSTGRESDB_DATABASE=postgres
EOF

# Запуск сервисов
docker compose pull
docker compose up

echo "===================================================="
echo "Развертывание N8N завершено!"
echo "Доступ к Studio Supabase: http://localhost:8000"
echo "Логин: admin"
echo "Пароль: $DASHBOARD_PASSWORD"
echo "===================================================="
echo "Важные секреты (сохраните в безопасное место):"
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "JWT_SECRET: $JWT_SECRET"
echo "ANON_KEY: $ANON_KEY"
echo "SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY"
echo "SECRET_KEY_BASE: $SECRET_KEY_BASE"
echo "VAULT_ENC_KEY: $VAULT_ENC_KEY"
echo "Логин N8N: n8nadmin"
echo "N8N_PASSWORD: $N8N_PASSWORD"
echo "===================================================="