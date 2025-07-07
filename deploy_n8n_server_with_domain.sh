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

# Запрос доменного имени
read -p "Введите доменное имя для проекта (например: example.com): " DOMAIN_NAME
while [[ -z "$DOMAIN_NAME" ]]; do
    echo "Ошибка: Доменное имя не может быть пустым!"
    read -p "Пожалуйста, введите доменное имя: " DOMAIN_NAME
done

mkdir -p nginx-proxy/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx-proxy/certs/privkey.pem \
  -out nginx-proxy/certs/fullchain.pem \
  -subj "/CN=*.$DOMAIN_NAME" \
  -addext "subjectAltName=DNS:$DOMAIN_NAME"

# Генерация поддоменов
SUPABASE_SUBDOMAIN="supabase.$DOMAIN_NAME"
N8N_SUBDOMAIN="n8n.$MAIN_DOMAIN"

cd nginx-proxy
# Создаем конфиг Nginx
cat > config/nginx.conf <<EOF
events {
    worker_connections  1024;
}

http {
    server {
        listen 80;
        server_name $DOMAIN_NAME *.$DOMAIN_NAME;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN_NAME services.$DOMAIN_NAME;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }
    }

    server {
        listen 443 ssl;
        server_name $SUPABASE_SUBDOMAIN;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;

        location / {
            proxy_pass http://kong:8000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }

    server {
        listen 443 ssl;
        server_name $N8N_SUBDOMAIN;

        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;

        location / {
            proxy_pass http://n8n:5678;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
}
EOF

# Замена DOMAIN в index.html
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/{{DOMAIN}}/$MAIN_DOMAIN/g" static/index.html
else
    # Linux и другие
    sed -i "s/{{DOMAIN}}/$MAIN_DOMAIN/g" static/index.html
fi

echo "Запуск nginx!"
docker compose pull
docker compose up -d

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
echo "Генерация секретов!"
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

cd ../supabase

# Обновление .env файла supabase
echo "Создание энвов!"
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
SITE_URL=https://$SUPABASE_SUBDOMAIN
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=https://$SUPABASE_SUBDOMAIN

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
SUPABASE_PUBLIC_URL=https://$SUPABASE_SUBDOMAIN

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
docker network inspect shared_gateway >/dev/null 2>&1 || \
    docker network create --driver bridge shared_gateway

# Запуск сервисов
docker compose pull
docker compose up -d

echo "===================================================="
echo "Развертывание Supabase завершено!"
echo "===================================================="


echo "Начинаем развертывание n8n"
N8N_PASSWORD=$(openssl rand -hex 16)
cd ../n8n

# Обновление .env файла n8n
envsubst <<EOF > .env
# N8N_HOST=n8n.example.ru
N8N_HOST=$N8N_SUBDOMAIN
# n8n auth
N8N_BASIC_AUTH_USER=n8nadmin
N8N_BASIC_AUTH_PASSWORD=$N8N_PASSWORD
GENERIC_TIMEZONE=Europe/Moscow
# database
DB_POSTGRESDB_PASSWORD=$POSTGRES_PASSWORD
#DB_POSTGRESDB_USER=n8n.$POOLER_TENANT_ID
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_HOST=db
DB_POSTGRESDB_DATABASE=postgres
EOF

# Запуск сервисов
docker compose pull
docker compose up -d

echo "===================================================="
echo "Развертывание N8N завершено!"
echo "Доступ к Studio Supabase: https://$SUPABASE_SUBDOMAIN"
echo "Логин: admin"
echo "Пароль: $DASHBOARD_PASSWORD"
echo "===================================================="
echo "Важные секреты (сохраните в безопасное место):"
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "JWT_SECRET: $JWT_SECRET"
echo "ANON_KEY: $ANON_KEY"
echo "SERVICE_ROLE_KEY: $SERVICE_ROLE_KEY"
echo "POOLER_TENANT_ID: $POOLER_TENANT_ID"
echo "SECRET_KEY_BASE: $SECRET_KEY_BASE"
echo "VAULT_ENC_KEY: $VAULT_ENC_KEY"
echo "Доступ к N8N: https://$N8N_SUBDOMAIN"
echo "Логин N8N: n8nadmin"
echo "N8N_PASSWORD: $N8N_PASSWORD"
echo "===================================================="