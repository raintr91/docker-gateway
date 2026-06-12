# Local dev — quy ước

Chỉnh **`routes.json`** (`cp routes.json.example routes.json`). Cần `python3` (parser: `lib/routes-emit.py`).

## Quy ước

- Mọi `host` trong JSON: **`something.<SSL_DOMAIN_BASE>`** (vd. `saas-api.local.com`). Cert SAN: `SSL_DOMAIN_BASE` + `*.<base>` — không đọc từng host khi gen SSL.
- File cert nginx: `certs/${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt` + `.key` (mount vào gateway `/etc/nginx/certs/`).
- **API / portal không publish cổng ra host** — gateway proxy qua `base_shared_net`:
  - API: `<stack>-api-nginx:80` — `stack` trong `api.stack` (khớp `API_STACK_PREFIX` ở compose, repo có thể ở workspace khác)
  - Portal: `<stack>-portal-node:3000` — cố định; `pnpm dev` chỉ trong container
- **`internal`**: Host header gateway gửi vào nginx PHP (khớp `server_name` trong `default.conf`); đặt trong `api.internal`.
- **Mairy external** vẫn dùng cổng publish host (sẽ bỏ sau).
- Thêm project: sửa JSON → `make gen-sites` + `make hosts`. **Không** cần `make gen-ssl` lại.

## Schema (tóm tắt)

- `shared[]`: `{ "title", "hosts": [...] }`
- `projects.<slug>`: `{ "api": { host, stack, internal }, "portals": [{ host, stack }] }` hoặc `{ "external": true, "sites": [...] }`
- `<slug>` project = nhóm trong hosts file; **`stack`** = tên container trên Docker network (có thể khác slug).

## Lệnh

```bash
make gen-sites   # infra từ sites.example + project từ routes.json
make init-sites  # chỉ infra (phpmyadmin, mail, mock, …)
make hosts       # hosts.sample
make gen-ssl     # cert ${PROJECT_NAME}.${SSL_DOMAIN_BASE}.crt + gen-sites + nhắc Windows trust
```
