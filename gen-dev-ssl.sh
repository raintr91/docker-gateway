#!/usr/bin/env bash
# Local dev — một flow: ghi đè server cert, copy bundle Windows, gen gateway.
# SAN từ .env: SSL_DOMAIN_BASE → base + *.<base>. Quy ước: ROUTES.md
#
# Usage:
#   bash gen-dev-ssl.sh [.env] [certs]
#   sh gen-dev-ssl.sh …   # cũng được: tự chuyển sang bash (dash không có pipefail)

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="${1:-$PROJECT_ROOT/.env}"
CERT_DIR="${2:-$PROJECT_ROOT/certs}"

CA_CERT="$CERT_DIR/dev-rootCA.crt"
CA_KEY="$CERT_DIR/dev-rootCA.key"
CA_SERIAL="$CERT_DIR/dev-rootCA.srl"
SERVER_KEY="$CERT_DIR/dev-server.key"
SERVER_CSR="$CERT_DIR/dev-server.csr"
SERVER_CERT="$CERT_DIR/dev-server.crt"
SERVER_CHAIN="$CERT_DIR/dev-server.fullchain.crt"
SERVER_PFX="$CERT_DIR/dev-server.pfx"
OPENSSL_CNF="$CERT_DIR/dev-server-openssl.cnf"
WINDOWS_BAT="$CERT_DIR/install-windows-trust.bat"
WINDOWS_PS1="$CERT_DIR/install-windows-trust.ps1"

CA_SUBJECT="/C=VN/ST=HN/L=HN/O=demo_unittest/OU=LocalDev/CN=demo_unittest Local Dev Root CA"
DAYS_CA="${DAYS_CA:-3650}"
DAYS_SERVER="${DAYS_SERVER:-825}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "[ERROR] Missing env file: $ENV_FILE" >&2
    exit 1
fi

mkdir -p "$CERT_DIR"

read_env() {
    local key="$1"
    local value
    value="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
    value="${value%\"}"
    value="${value#\"}"
    value="${value//$'\r'/}"
    echo "$value"
}

load_ssl_domains_from_env() {
    local ssl_base

    ssl_base="$(read_env SSL_DOMAIN_BASE)"
    ssl_base="$(echo "$ssl_base" | xargs)"
    ssl_base="${ssl_base#.}"
    [[ -n "$ssl_base" ]] || ssl_base="local.com"

    DOMAINS=("$ssl_base" "*.$ssl_base")
    COMMON_NAME="*.$ssl_base"
}

build_openssl_config() {
    local cn="$1"
    {
        echo "[req]"
        echo "default_bits = 2048"
        echo "prompt = no"
        echo "default_md = sha256"
        echo "distinguished_name = dn"
        echo "req_extensions = req_ext"
        echo
        echo "[dn]"
        echo "CN = $cn"
        echo
        echo "[req_ext]"
        echo "subjectAltName = @alt_names"
        echo "basicConstraints = critical,CA:FALSE"
        echo "keyUsage = critical,digitalSignature,keyEncipherment"
        echo "extendedKeyUsage = serverAuth"
        echo "subjectKeyIdentifier = hash"
        echo
        echo "[v3_server]"
        echo "subjectAltName = @alt_names"
        echo "basicConstraints = critical,CA:FALSE"
        echo "keyUsage = critical,digitalSignature,keyEncipherment"
        echo "extendedKeyUsage = serverAuth"
        echo "subjectKeyIdentifier = hash"
        echo "authorityKeyIdentifier = keyid,issuer"
        echo
        echo "[alt_names]"

        local i=1
        local d
        for d in "${DOMAINS[@]}"; do
            echo "DNS.$i = $d"
            ((i++))
        done
    } >"$OPENSSL_CNF"
}

create_ca_if_missing() {
    if [[ -f "$CA_CERT" && -f "$CA_KEY" ]]; then
        echo "[INFO] Reusing existing local root CA: $CA_CERT"
        return
    fi

    echo "[INFO] Generating local root CA..."
    openssl genrsa -out "$CA_KEY" 4096
    openssl req -x509 -new -nodes -sha256 -days "$DAYS_CA" \
        -key "$CA_KEY" \
        -subj "$CA_SUBJECT" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -out "$CA_CERT"
}

generate_server_cert() {
    local common_name="$1"

    if [[ -f "$SERVER_KEY" || -f "$SERVER_CHAIN" ]]; then
        echo "[INFO] Ghi đè cert cũ → $SERVER_CHAIN"
    else
        echo "[INFO] Tạo server cert: $common_name"
    fi
    build_openssl_config "$common_name"

    openssl genrsa -out "$SERVER_KEY" 2048
    openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$OPENSSL_CNF"
    openssl x509 -req -sha256 -days "$DAYS_SERVER" \
        -in "$SERVER_CSR" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -out "$SERVER_CERT" \
        -extensions v3_server \
        -extfile "$OPENSSL_CNF"

    cat "$SERVER_CERT" "$CA_CERT" >"$SERVER_CHAIN"

    openssl pkcs12 -export \
        -out "$SERVER_PFX" \
        -inkey "$SERVER_KEY" \
        -in "$SERVER_CERT" \
        -certfile "$CA_CERT" \
        -passout pass:

    rm -f "$SERVER_CSR"
}

install_ca_into_wsl() {
    if ! command -v update-ca-certificates >/dev/null 2>&1; then
        echo "[WARN] update-ca-certificates is not available. Skip WSL trust install."
        return 0
    fi

    local target_ca="/usr/local/share/ca-certificates/demo-unittest-dev-rootCA.crt"

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        if cp "$CA_CERT" "$target_ca" && update-ca-certificates; then
            echo "[INFO] WSL trust store updated."
            return 0
        fi
    else
        if sudo cp "$CA_CERT" "$target_ca" && sudo update-ca-certificates; then
            echo "[INFO] WSL trust store updated."
            return 0
        fi
    fi

    echo "[WARN] WSL trust store not updated (sudo needs password or copy failed)." >&2
    return 1
}

generate_windows_bat() {
    cat >"$WINDOWS_BAT" <<'BAT'
@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "CERT_FILE=%SCRIPT_DIR%dev-rootCA.crt"
set "CERT_SUBJECT=CN=demo_unittest Local Dev Root CA"
set "PS1_FILE=%SCRIPT_DIR%install-windows-trust.ps1"

if not exist "%CERT_FILE%" (
  echo [ERROR] Certificate file not found: %CERT_FILE%
  exit /b 1
)

set "RUN_AS_ADMIN=0"
net session >nul 2>&1
if %errorlevel%==0 set "RUN_AS_ADMIN=1"

if "%RUN_AS_ADMIN%"=="1" (
    echo [INFO] Running as Administrator: importing into LocalMachine + CurrentUser trust stores...
    certutil -addstore -f Root "%CERT_FILE%" >nul
    certutil -addstore -f CA "%CERT_FILE%" >nul
    certutil -user -addstore -f Root "%CERT_FILE%" >nul
    certutil -user -addstore -f CA "%CERT_FILE%" >nul
) else (
    echo [WARN] Not running as Administrator. Importing into CurrentUser stores only.
    certutil -user -addstore -f Root "%CERT_FILE%" >nul
    certutil -user -addstore -f CA "%CERT_FILE%" >nul
)

if errorlevel 1 (
    echo [ERROR] Failed to import certificate into trust stores.
    exit /b 1
)

echo [INFO] Verifying certificate in CurrentUser Root store...
certutil -user -store Root "%CERT_SUBJECT%" | findstr /i "%CERT_SUBJECT%" >nul
if errorlevel 1 (
    echo [ERROR] Could not verify certificate in CurrentUser Root store.
    exit /b 1
)

echo [INFO] Clearing URL cache to refresh cert chain resolution...
certutil -urlcache * delete >nul 2>&1

if exist "%PS1_FILE%" (
    echo [INFO] Running PowerShell trust fix script...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%" -CertPath "%CERT_FILE%" -EnableFirefoxEnterpriseRoots
)

echo [NOTE] If browser still warns, close all browser windows and reopen.
echo [NOTE] Firefox may use its own trust store; enable Enterprise Roots in Firefox policies if needed.

echo [DONE] Certificate imported successfully.
exit /b 0
BAT

    echo "[INFO] Generated Windows trust script: $WINDOWS_BAT"
}

generate_windows_ps1() {
    cat >"$WINDOWS_PS1" <<'PS1'
param(
    [Parameter(Mandatory=$false)]
    [string]$CertPath = "$PSScriptRoot\dev-rootCA.crt",
    [switch]$EnableFirefoxEnterpriseRoots
)

$ErrorActionPreference = "Stop"

function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Import-RootCert {
    param(
        [string]$Path,
        [string]$StorePath
    )

    if (-not (Test-Path $Path)) {
        throw "Certificate file not found: $Path"
    }

    Import-Certificate -FilePath $Path -CertStoreLocation $StorePath | Out-Null
}

function Ensure-FirefoxEnterpriseRoots {
    $policiesContent = @"
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true
    }
  }
}
"@

    $paths = @(
        "$env:ProgramFiles\Mozilla Firefox\distribution",
        "$env:ProgramFiles(x86)\Mozilla Firefox\distribution"
    )

    foreach ($dir in $paths) {
        if (Test-Path (Split-Path $dir -Parent)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path (Join-Path $dir "policies.json") -Value $policiesContent -Encoding UTF8
        }
    }
}

Write-Host "[INFO] Importing certificate: $CertPath"

Import-RootCert -Path $CertPath -StorePath "Cert:\CurrentUser\Root"
Import-RootCert -Path $CertPath -StorePath "Cert:\CurrentUser\CA"

if (Test-Admin) {
    Write-Host "[INFO] Administrator detected. Importing into LocalMachine stores..."
    Import-RootCert -Path $CertPath -StorePath "Cert:\LocalMachine\Root"
    Import-RootCert -Path $CertPath -StorePath "Cert:\LocalMachine\CA"
} else {
    Write-Host "[WARN] Not running as Administrator. LocalMachine stores were not updated."
}

if ($EnableFirefoxEnterpriseRoots) {
    if (Test-Admin) {
        Write-Host "[INFO] Enabling Firefox enterprise root trust policy..."
        Ensure-FirefoxEnterpriseRoots
    } else {
        Write-Host "[WARN] Firefox policy update skipped (requires Administrator)."
    }
}

Write-Host "[INFO] Flushing DNS and URL cert cache..."
ipconfig /flushdns | Out-Null
certutil -urlcache * delete | Out-Null

Write-Host "[DONE] Windows trust setup completed. Close and reopen browser(s)."
PS1

    echo "[INFO] Generated Windows PowerShell script: $WINDOWS_PS1"
}

copy_windows_bundle_if_available() {
    if [[ ! -d "/mnt/c/Users/Public" ]]; then
        echo "[WARN] Skip Windows bundle copy: /mnt/c/Users/Public not found (need WSL + Windows C: mounted)." >&2
        return
    fi

    local project_name
    project_name="$(read_env PROJECT_NAME)"
    project_name="${project_name:-demo_unittest}"
    project_name="${project_name//[^a-zA-Z0-9._-]/}"
    [[ -z "$project_name" ]] && project_name="demo_unittest"

    local public_dev_ssl="/mnt/c/Users/Public/dev_ssl"
    local out_dir="${public_dev_ssl}/${project_name}"

    mkdir -p "$public_dev_ssl"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    cp -f "$CA_CERT" "$out_dir/dev-rootCA.crt"
    cp -f "$WINDOWS_BAT" "$out_dir/install-windows-trust.bat"
    cp -f "$WINDOWS_PS1" "$out_dir/install-windows-trust.ps1"
    cp -f "$SERVER_CERT" "$out_dir/dev-server.crt"
    cp -f "$SERVER_KEY" "$out_dir/dev-server.key"
    cp -f "$SERVER_PFX" "$out_dir/dev-server.pfx"
    echo "[INFO] Copied Windows bundle to: $out_dir"
    echo "[INFO] Windows path: C:\\Users\\Public\\dev_ssl\\${project_name}\\"
}

load_ssl_domains_from_env
create_ca_if_missing
generate_server_cert "$COMMON_NAME"
generate_windows_bat
generate_windows_ps1
copy_windows_bundle_if_available
install_ca_into_wsl || true

bash "$SCRIPT_DIR/gen-gateway-sites.sh" "$ENV_FILE"

project_name="$(read_env PROJECT_NAME)"
project_name="${project_name:-demo_unittest}"
project_name="${project_name//[^a-zA-Z0-9._-]/}"
[[ -z "$project_name" ]] && project_name="demo_unittest"
win_dir="C:\\Users\\Public\\dev_ssl\\${project_name}"

echo
echo "[DONE] Cert: $SERVER_CHAIN"
echo
echo "  Windows — chạy lại (Admin), kể cả khi WSL đã trust mà Chrome vẫn báo lỗi:"
echo "    ${win_dir}\\install-windows-trust.bat"
echo "  Hoặc trong WSL: $WINDOWS_BAT"
echo
echo "  Thêm project: chỉ make gen-sites && make hosts (không cần chạy lại script này)."
