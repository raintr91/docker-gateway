# Dev Environment (Docker Gateway)

Hạ tầng local dùng chung: **gateway HTTPS**, MySQL, PostgreSQL, LocalStack, Mailpit, mock API.  
Các project (API, portal, …) **có thể nằm ở bất kỳ thư mục nào** — chỉ cần container join đúng Docker network và khớp `routes.json`.

## Cấu trúc repo này

```
dev_env/
├── .env                      ← cấu hình chính (cp từ .env.example)
├── routes.json               ← domain + upstream (cp từ routes.json.example — không commit)
├── docker-compose.yml        ← gateway, MySQL, phpMyAdmin, pgAdmin
├── docker-compose.services.yml   ← LocalStack, Mailpit, mock, StackPort
├── gateway/sites/            ← nginx conf cá nhân (make gen-sites — không commit)
├── gateway/sites.example/    ← template infra trong git (phpmyadmin, pgadmin, …)
├── certs/                    ← TLS local
└── Makefile                  ← make help
```

## Bắt đầu nhanh (dev_env)

```bash
cp .env.example .env
cp routes.json.example routes.json
make gen-sites        # copy infra từ sites.example + sinh conf project từ routes.json
make gen-ssl          # lần đầu: cert + gateway sites
make hosts            # hosts.sample → /etc/hosts (WSL + Windows)
make d-up             # gateway + DB
make d-services-up    # LocalStack, Mailpit, mock, StackPort (tùy chọn)
```

Sau đó bật compose của từng project (xem mục dưới). Chi tiết lệnh: **`make help`**

## Cấu hình `.env`

| Biến | Mô tả |
|------|--------|
| `PROJECT_NAME` | Tiền tố container/volume của stack gateway |
| `SSL_DOMAIN_BASE` | Suffix domain (vd. `local.com`) |
| `BASE_SHARED_NETWORK_NAME` | **Tên mạng Docker chung** — project bên ngoài phải dùng cùng giá trị |
| `HOSTS_IP` | IP ghi vào hosts (thường `127.0.0.1`) |
| `HOST_UID` / `HOST_GID` | Khớp user host (`id -u`, `id -g`) |

## Docker cho project (ở ngoài `dev_env`)

### Nguyên tắc

1. **Bật gateway trước** — `make d-up` tạo mạng `base_shared_net` (hoặc tên trong `BASE_SHARED_NETWORK_NAME`).
2. **Compose project join mạng external** — không tạo mạng riêng, không publish cổng app ra host (gateway proxy).
3. **Đăng ký domain** trong `routes.json` → `make gen-sites` + `make hosts` + `make gw-restart`.
4. **`stack` trong JSON** phải khớp tiền tố tên container trên mạng.

### Quy ước tên container (gateway proxy tới)

| Loại | Tên container | Cổng trong mạng |
|------|---------------|-----------------|
| API (Laravel) | `<stack>-api-nginx` | 80 |
| Portal (Nuxt) | `<stack>-portal-node` | 3000 |

Ví dụ `routes.json`: `"stack": "saas"` → gateway gọi `saas-api-nginx:80`.  
Portal: `"stack": "saas-admin"` → `saas-admin-portal-node:3000`.

### Mẫu `docker-compose.yml` — API

Đặt trong project bất kỳ (vd. `~/workspace/my-api/docker/`):

```yaml
name: api-${API_STACK_PREFIX:-myapp}

services:
  api-php:
    container_name: ${API_STACK_PREFIX:-myapp}-api-php
    # build / volumes …
    networks:
      - shared

  api-nginx:
    container_name: ${API_STACK_PREFIX:-myapp}-api-nginx
    image: nginx:1.27-alpine
    depends_on: [api-php]
    # volumes / default.conf …
    networks:
      - shared

networks:
  shared:
    name: ${BASE_SHARED_NETWORK_NAME:-base_shared_net}
    external: true
```

`.env` của project:

```bash
API_STACK_PREFIX=myapp
BASE_SHARED_NETWORK_NAME=base_shared_net   # khớp dev_env/.env
HOST_UID=1000
HOST_GID=1000
```

Chạy (từ thư mục chứa compose):

```bash
docker compose --env-file .env up -d
```

### Mẫu `docker-compose.yml` — Portal (Nuxt)

```yaml
name: portal-${PORTAL_STACK_PREFIX:-myapp}

services:
  frontend-node:
    container_name: ${PORTAL_STACK_PREFIX:-myapp}-portal-node
    # image node:24, pnpm dev listen :3000 …
    networks:
      - shared

networks:
  shared:
    name: ${BASE_SHARED_NETWORK_NAME:-base_shared_net}
    external: true
```

`.env`:

```bash
PORTAL_STACK_PREFIX=myapp-admin
BASE_SHARED_NETWORK_NAME=base_shared_net
```

### Đăng ký gateway

Thêm vào `dev_env/routes.json`:

```json
"myproject": {
  "api": {
    "host": "myapp-api.local.com",
    "stack": "myapp",
    "internal": "myapp-api.local.com"
  },
  "portals": [
    { "host": "myapp-admin.local.com", "stack": "myapp-admin" }
  ]
}
```

Rồi trong `dev_env`:

```bash
make gen-sites
make hosts
make gw-restart
```

Trình duyệt: `https://myapp-api.local.com` (sau SSL + hosts).

### Kết nối DB / dịch vụ shared từ container project

Trên `base_shared_net`, dùng **tên service Docker** (không dùng `127.0.0.1`):

| Dịch vụ | Host trong container |
|---------|----------------------|
| MySQL 8.4 | `mysql` |
| PostgreSQL | `postgres` / alias `saas-postgres` |
| Redis | `redis` :6379 |
| LocalStack | `localstack` |
| Mailpit SMTP | `mailpit` :1025 |
| HTTPS tới domain local | `https://mail.local.com` (gateway resolve qua DNS alias trên mạng) |

MySQL cũng expose `127.0.0.1:3306` ra host nếu cần chạy artisan/test ngoài container.

### Checklist project mới

- [ ] `BASE_SHARED_NETWORK_NAME` khớp `dev_env/.env`
- [ ] Container đặt tên đúng `<stack>-api-nginx` / `<stack>-portal-node`
- [ ] Không `ports:` publish cổng app (443/80 do gateway lo)
- [ ] Đã thêm host vào `routes.json`
- [ ] `make gen-sites` + `make hosts` + `make gw-restart`
- [ ] `make d-up` chạy trước khi `docker compose up` project

## Hosts file

`make hosts` ghi `hosts.sample` và merge vào:
- **WSL:** `/etc/hosts`
- **Windows:** `C:\Windows\System32\drivers\etc\hosts`

## Lệnh Makefile

| Nhóm | Lệnh |
|------|------|
| Gateway + DB | `d-up`, `d-down`, `d-ps`, `d-logs` |
| Dev services | `d-services-up`, `d-up-all`, `d-down-all` |
| Cấu hình | `gen-sites`, `gen-ssl`, `hosts`, `gw-restart` |
| Exec shell | `make exec SVC=gateway`, `make exec mysql`, `make exec-list` |
| Dừng hết | `stop-all`, `down-all` |

## URL (sau hosts + SSL)

| Dịch vụ | URL |
|---------|-----|
| API / Portal project | Theo `routes.json` |
| phpMyAdmin | https://phpmyadmin.local.com |
| pgAdmin | https://pgadmin.local.com |
| Redis Commander | https://redisadmin.local.com |
| Mailpit | http://mail.local.com |
| Mock API | http://mock.local.com |
| StackPort | http://stackport.local.com |

## SSL (WSL + Windows)

```bash
make gen-ssl
# Windows (Admin): C:\Users\Public\dev_ssl\<PROJECT_NAME>\install-windows-trust.bat
```

Chi tiết domain: **`ROUTES.md`**

## Ghi chú

- Nhiều clone `dev_env` trên một máy: đặt `BASE_SHARED_NETWORK_NAME` **khác nhau** mỗi clone; project `.env` phải khớp clone đang dùng.
- Lỗi mạng: `make d-down` → `docker network rm base_shared_net` → `make d-up`.
- Thêm host mới: sửa `routes.json` → `make gen-sites` — **không** cần `make gen-ssl` lại.
