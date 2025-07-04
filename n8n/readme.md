для подключения n8n - зайти в супабейс и создать роль n8n
добавить в скрипт supabase-project/volumes/db/roles.sql
```
ALTER USER n8n WITH PASSWORD :'pgpass';
```

создать схему n8n добавить в файл supabase-project/volumes/db/init/data.sql
CREATE if not exists schema n8n

GRANT ALL PRIVILEGES ON DATABASE "postgres" to n8n;

GRANT ALL PRIVILEGES ON schema "n8n" to n8n;

Чтобы оставить n8n в отдельном docker-compose файле и интегрировать его с Supabase через Kong, выполните следующие шаги:

### 1. Создайте общую Docker сеть
Добавьте в оба docker-compose.yaml сеть с одинаковым названием:

```bash
docker network create shared_gateway
```

### 2. Измените docker-compose для Supabase (supabase/docker-compose.yml)
Добавьте в сервис Kong:
```yaml
services:
  kong:
    networks:
      - supabase_network
      - shared_gateway  # Добавляем общую сеть
    volumes:
      - ./certs:/etc/kong/certs  # Монтируем папку с сертификатами

networks:
  shared_gateway:
    external: true  # Используем внешнюю сеть
```

### 3. Измените docker-compose для n8n (n8n/docker-compose.yml)
```yaml
version: '3.8'

services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=n8n.tdg.ru
      - N8N_PORT=5678
      - N8N_PROTOCOL=http  # Kong будет обрабатывать HTTPS
      - WEBHOOK_URL=https://n8n.tdg.ru/
      - N8N_BASIC_AUTH_ACTIVE=false  # Аутентификацию будем делать в Kong
      # Остальные переменные...
    networks:
      - n8n_network
      - shared_gateway  # Подключаем к общей сети

networks:
  shared_gateway:
    external: true
```

### 4. Обновите конфигурацию Kong (kong.yml)
Добавьте в конец файла:
```yaml
###
### n8n Configuration
###
services:
  - name: n8n
    url: http://n8n:5678/  # Используем имя сервиса из docker-compose
    routes:
      - name: n8n-route
        protocols: [http, https]
        hosts: ["n8n.tdg.ru"]
        strip_path: false

###
### SSL Configuration
###
certificates:
  - cert: /etc/kong/certs/fullchain.pem
    key: /etc/kong/certs/privkey.pem
    snis: ["*.tdg.ru"]
```

### 5. Настройка сертификатов
1. Сгенерируйте wildcard-сертификат:
```bash
certbot certonly --manual --preferred-challenges=dns -d "*.tdg.ru"
```

2. Создайте папку для сертификатов в проекте Supabase:
```bash
mkdir supabase/certs
```

3. Скопируйте сертификаты:
```bash
cp /etc/letsencrypt/live/tdg.ru/fullchain.pem supabase/certs/
cp /etc/letsencrypt/live/tdg.ru/privkey.pem supabase/certs/
```

### 6. Запуск сервисов
```bash
# Запустите Supabase
cd supabase
docker-compose up -d

# Запустите n8n
cd ../n8n
docker-compose up -d
```

### 7. Настройка аутентификации (опционально)
Если нужно сохранить аутентификацию, добавьте в конфиг Kong для n8n:

```yaml
plugins:
  - name: basic-auth
    config:
      hide_credentials: true
  - name: acl
    config:
      allow: [admin]
```

Создайте пользователя через Kong Admin API:
```bash
curl -X POST http://localhost:8001/consumers \
  --data "username=n8n_user"

curl -X POST http://localhost:8001/consumers/n8n_user/basic-auth \
  --data "username=admin" \
  --data "password=securepassword"
```

### 8. Обновление сертификатов
Добавьте в cron:
```bash
0 3 * * * certbot renew && cp /etc/letsencrypt/live/tdg.ru/*.pem /path/to/supabase/certs/ && docker restart supabase-kong-1
```

### Ключевые моменты:
1. **Сетевое взаимодействие**:
   - Сервисы общаются через общую сеть `shared_gateway`
   - Kong обращается к n8n по DNS-имени `n8n` (имя сервиса в docker-compose)

2. **Безопасность**:
   - n8n слушает только HTTP (5678)
   - HTTPS терминация происходит на Kong
   - Порт 5678 не экспортируется наружу

3. **Разделение ответственности**:
   - Kong: роутинг, SSL, аутентификация
   - n8n: только бизнес-логика

4. **Обновление конфигурации**:
   - При изменении kong.yml перезапустите Kong:
     ```bash
     docker restart supabase-kong-1
     ```

Это решение позволяет:
- Сохранить раздельные docker-compose файлы
- Использовать единую точку входа (Kong)
- Обойти проблемы с получением сертификатов в РФ
- Централизовать управление доступом
- Легко масштабировать систему