#!/bin/sh
set -e  # エラーが発生したら即停止

# カラー出力用の設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ関数（printf使用でPOSIX準拠）
log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

# クリーンアップ関数（インストール失敗時）
cleanup_on_error() {
    log_error "Installation failed. Cleaning up..."

    # Stop and disable supervisor service if it was started
    if systemctl is-active --quiet agenticsec-supervisor 2>/dev/null; then
        systemctl stop agenticsec-supervisor
        log_info "  Stopped agenticsec-supervisor service"
    fi

    if systemctl is-enabled --quiet agenticsec-supervisor 2>/dev/null; then
        systemctl disable agenticsec-supervisor
        log_info "  Disabled agenticsec-supervisor service"
    fi

    # Remove supervisor systemd service file
    if [ -f /etc/systemd/system/agenticsec-supervisor.service ]; then
        rm /etc/systemd/system/agenticsec-supervisor.service
        log_info "  Removed agenticsec-supervisor service file"
    fi

    # Stop and disable fluent-bit service if it was started
    if systemctl is-active --quiet agenticsec-fluent-bit 2>/dev/null; then
        systemctl stop agenticsec-fluent-bit
        log_info "  Stopped agenticsec-fluent-bit service"
    fi

    if systemctl is-enabled --quiet agenticsec-fluent-bit 2>/dev/null; then
        systemctl disable agenticsec-fluent-bit
        log_info "  Disabled agenticsec-fluent-bit service"
    fi

    # Remove fluent-bit systemd service file
    if [ -f /etc/systemd/system/agenticsec-fluent-bit.service ]; then
        rm /etc/systemd/system/agenticsec-fluent-bit.service
        log_info "  Removed agenticsec-fluent-bit service file"
    fi

    # Reload systemd
    systemctl daemon-reload

    # Remove upgrade check script
    if [ -f /usr/local/bin/agenticsec-supervisor-check-upgrade.sh ]; then
        rm /usr/local/bin/agenticsec-supervisor-check-upgrade.sh
        log_info "  Removed upgrade check script"
    fi

    # Remove configuration directories
    if [ -d /etc/agenticsec ]; then
        rm -rf /etc/agenticsec
        log_info "  Removed /etc/agenticsec/"
    fi

    # Remove log directories
    if [ -d /var/log/agenticsec ]; then
        rm -rf /var/log/agenticsec
        log_info "  Removed /var/log/agenticsec/"
    fi

    # Remove supervisor Docker image
    if [ -n "$SUPERVISOR_IMAGE" ]; then
        if docker image inspect "$SUPERVISOR_IMAGE" >/dev/null 2>&1; then
            docker rmi "$SUPERVISOR_IMAGE" >/dev/null 2>&1
            log_info "  Removed Docker image: $SUPERVISOR_IMAGE"
        fi
    fi

    # Remove fluent-bit Docker image
    if docker image inspect fluent/fluent-bit:latest >/dev/null 2>&1; then
        docker rmi fluent/fluent-bit:latest >/dev/null 2>&1
        log_info "  Removed Docker image: fluent/fluent-bit:latest"
    fi

    log_error "Cleanup completed. Please resolve the issue and try again."
}

# Legacy rapidpen-* resources cleanup (pre-install)
cleanup_legacy_services() {
    found_legacy=false
    for service in rapidpen-supervisor.service rapidpen-fluent-bit.service rapidpen-log-cleanup.timer rapidpen-log-cleanup.service; do
        if [ -f "/etc/systemd/system/$service" ]; then
            found_legacy=true
            log_info "  Found legacy service: $service, removing..."
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/$service"
        fi
    done
    if [ "$found_legacy" = true ]; then
        systemctl daemon-reload
        log_info "  Legacy services cleaned up"
    fi
    # Legacy files/directories
    for legacy_dir in /etc/rapidpen /var/log/rapidpen; do
        if [ -d "$legacy_dir" ]; then
            rm -rf "$legacy_dir"
            log_info "  Removed legacy directory: $legacy_dir"
        fi
    done
    for legacy_file in /usr/local/bin/rapidpen-supervisor-check-upgrade.sh /usr/local/bin/rapidpen-log-cleanup.sh /usr/bin/rapidpen-uninstall; do
        if [ -f "$legacy_file" ]; then
            rm -f "$legacy_file"
            log_info "  Removed legacy file: $legacy_file"
        fi
    done
    # Legacy Docker resources
    if command -v docker > /dev/null 2>&1; then
        for container in rapidpen-supervisor rapidpen-fluent-bit; do
            if docker ps -a 2>/dev/null | grep -q "$container"; then
                docker rm -f "$container" > /dev/null 2>&1
                log_info "  Removed legacy container: $container"
            fi
        done
        if docker volume inspect rapidpen-fluent-bit-data >/dev/null 2>&1; then
            docker volume rm rapidpen-fluent-bit-data > /dev/null 2>&1
            log_info "  Removed legacy volume: rapidpen-fluent-bit-data"
        fi
    fi
}

echo "==========================="
echo "  AgenticSec Edge Installer  "
echo "==========================="
echo ""

# 1. root権限チェック（POSIX準拠）
log_info "Checking root privileges..."
if [ "$(id -u)" -ne 0 ]; then
   log_error "This script must be run as root (use sudo)"
   echo "Usage: sudo sh $0"
   exit 1
fi
log_info "✓ Running as root"

# 2. Dockerの存在確認と環境検出
log_info "Checking Docker installation..."

# Dockerバイナリパス検出
DOCKER_BIN=$(command -v docker 2>/dev/null) || DOCKER_BIN=""
if [ -z "$DOCKER_BIN" ]; then
    log_error "Docker is not installed"
    echo ""
    echo "Please install Docker first:"
    echo "  Ubuntu/Debian: sudo apt-get install docker.io"
    echo "  Or visit: https://docs.docker.com/engine/install/"
    exit 1
fi

# Dockerバージョン確認（情報のみ）
DOCKER_VERSION=$("$DOCKER_BIN" --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1) || DOCKER_VERSION=""
if [ -z "$DOCKER_VERSION" ]; then
    log_error "Docker is installed but not responding"
    echo ""
    echo "Please check if Docker daemon is running:"
    echo "  sudo systemctl status docker"
    exit 1
fi
log_info "✓ Docker found (version: $DOCKER_VERSION)"
log_info "  Docker binary: $DOCKER_BIN"

# Docker socket検出
log_info "Detecting Docker socket..."
DOCKER_SOCK=""

# 標準パスを確認
for sock_path in /var/run/docker.sock /run/docker.sock; do
    if [ -S "$sock_path" ]; then
        DOCKER_SOCK="$sock_path"
        break
    fi
done

# 見つからない場合はエラー
if [ -z "$DOCKER_SOCK" ]; then
    log_error "Docker socket not found"
    echo ""
    echo "Expected locations:"
    echo "  - /var/run/docker.sock"
    echo "  - /run/docker.sock"
    echo ""
    echo "Please check your Docker installation"
    exit 1
fi

log_info "✓ Docker socket found: $DOCKER_SOCK"

# Dockerデーモンの起動確認
log_info "Verifying Docker daemon is running..."
if ! "$DOCKER_BIN" info > /dev/null 2>&1; then
    log_error "Docker daemon is not running"
    echo ""
    echo "Please start Docker:"
    echo "  sudo systemctl start docker"
    echo ""
    echo "To enable Docker on boot:"
    echo "  sudo systemctl enable docker"
    exit 1
fi
log_info "✓ Docker daemon is running"

# Pre-install: Clean up legacy rapidpen-* resources
log_info "Checking for legacy rapidpen-* resources..."
cleanup_legacy_services

# 3. 必要なディレクトリ作成
log_info "Creating required directories..."

# /var/log/agenticsec/supervisor - Supervisorログ用
if [ ! -d "/var/log/agenticsec/supervisor" ]; then
    mkdir -p /var/log/agenticsec/supervisor
    log_info "  Created /var/log/agenticsec/supervisor/"
else
    log_info "  /var/log/agenticsec/supervisor/ already exists"
fi

# /var/log/agenticsec/operator - Operatorログ用
if [ ! -d "/var/log/agenticsec/operator" ]; then
    mkdir -p /var/log/agenticsec/operator
    chmod 777 /var/log/agenticsec/operator
    log_info "  Created /var/log/agenticsec/operator/"
else
    log_info "  /var/log/agenticsec/operator/ already exists"
fi

# 4. InstallerConfig生成
log_info "Creating installer configuration file..."

CONFIG_FILE="/etc/agenticsec/supervisor/installer_config.json"

# 設定ディレクトリが存在しない場合は作成
if [ ! -d "/etc/agenticsec/supervisor" ]; then
    mkdir -p /etc/agenticsec/supervisor
    chmod 700 /etc/agenticsec/supervisor
    log_info "  Created /etc/agenticsec/supervisor/"
else
    log_info "  /etc/agenticsec/supervisor/ already exists"
fi

# supervisor_id_candidate生成（デフォルト：sup-hostname）
DEFAULT_HOSTNAME=$(hostname)
SUPERVISOR_ID_CANDIDATE="sup-${DEFAULT_HOSTNAME}"

# InstallerConfig JSON を作成（テンプレートから生成）
SCRIPT_DIR=$(dirname "$0")
INSTALLER_CONFIG_TEMPLATE="$SCRIPT_DIR/templates/installer_config.json.template"

if [ -f "$INSTALLER_CONFIG_TEMPLATE" ]; then
    sed -e "s|{{SUPERVISOR_ID_CANDIDATE}}|$SUPERVISOR_ID_CANDIDATE|g" \
        -e "s|{{LOG_DIR_SUPERVISOR}}|/var/log/agenticsec/supervisor|g" \
        -e "s|{{LOG_DIR_OPERATOR_BASE}}|/var/log/agenticsec/operator|g" \
        "$INSTALLER_CONFIG_TEMPLATE" > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    log_info "  Created installer configuration: $CONFIG_FILE"
    log_info "  Supervisor ID: $SUPERVISOR_ID_CANDIDATE"
else
    log_error "Template not found: $INSTALLER_CONFIG_TEMPLATE"
    exit 1
fi

# 5. AgenticSec Cloud接続情報の入力
log_info "Configuring AgenticSec Cloud connection..."

# API Key入力（必須）
if [ -n "$AGENTICSEC_API_KEY" ]; then
    # 環境変数から取得（テスト用）
    log_info "  Using API Key from environment variable"
else
    # ユーザーから入力（TTYが必要）
    if [ ! -e /dev/tty ]; then
        log_error "No TTY available and AGENTICSEC_API_KEY environment variable is not set"
        log_error "  For non-interactive environments (e.g. cloud-init), set the environment variable:"
        log_error "    export AGENTICSEC_API_KEY='your-api-key'"
        exit 1
    fi
    echo ""
    echo "Please enter your AgenticSec Cloud API Key:"
    echo "(You can obtain this from AgenticSec Cloud Web UI)"
    printf "API Key: "
    read -r AGENTICSEC_API_KEY < /dev/tty

    # 空チェック
    while [ -z "$AGENTICSEC_API_KEY" ]; do
        log_error "API Key cannot be empty"
        printf "API Key: "
        read -r AGENTICSEC_API_KEY < /dev/tty
    done

    log_info "  API Key configured"
fi

# Base URL入力（オプション、デフォルト値あり）
DEFAULT_BASEURL="https://api.agenticsec.tech/api/edge/supervisor"

if [ -n "$AGENTICSEC_BASEURL" ]; then
    # 環境変数から取得（テスト用）
    log_info "  Using Base URL from environment variable: $AGENTICSEC_BASEURL"
else
    # ユーザーから入力（TTYが必要、無い場合はデフォルト値を使用）
    if [ ! -e /dev/tty ]; then
        AGENTICSEC_BASEURL="$DEFAULT_BASEURL"
        log_info "  No TTY available, using default base URL: $AGENTICSEC_BASEURL"
    else
        echo ""
        echo "AgenticSec Cloud Base URL (default: $DEFAULT_BASEURL)"
        echo "(Press Enter to use default, or enter custom URL)"
        printf "Base URL: "
        read -r AGENTICSEC_BASEURL < /dev/tty

        # 空の場合はデフォルト値を使用
        if [ -z "$AGENTICSEC_BASEURL" ]; then
            AGENTICSEC_BASEURL="$DEFAULT_BASEURL"
            log_info "  Using default base URL: $AGENTICSEC_BASEURL"
        else
            log_info "  Using custom base URL: $AGENTICSEC_BASEURL"
        fi
    fi
fi

# 6. SupervisorState 初期ファイル作成（後でimage_tagを更新）
log_info "Creating initial supervisor state file..."

STATE_FILE="/etc/agenticsec/supervisor/state.json"
STATE_TEMPLATE="$SCRIPT_DIR/templates/state.json.template"

# 仮のimage_tagで初期化（後でGHCRから取得したタグに更新）
if [ -f "$STATE_TEMPLATE" ]; then
    sed -e "s|{{IMAGE_TAG}}|PLACEHOLDER|g" \
        -e "s|{{AGENTICSEC_CLOUD_API_KEY}}|$AGENTICSEC_API_KEY|g" \
        -e "s|{{AGENTICSEC_CLOUD_BASEURL}}|$AGENTICSEC_BASEURL|g" \
        "$STATE_TEMPLATE" > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    log_info "  Created supervisor state: $STATE_FILE (image_tag will be updated after fetching image)"
else
    log_error "Template not found: $STATE_TEMPLATE"
    exit 1
fi

# 6. Supervisorイメージの最新版を取得
log_info "Fetching latest supervisor image from GHCR..."

# jq 実行用のヘルパー関数
jq_exec() {
    if command -v jq > /dev/null 2>&1; then
        # ローカルのjqを使用
        jq "$@"
    else
        # Dockerコンテナでjqを実行（stdinからパイプで入力すること）
        # NOTE: Docker版jqはホストのファイルパスを読めないため、
        #       必ず cat file | jq_exec ... のようにパイプで渡すこと
        _jq_output=$(docker run --rm -i imega/jq "$@" 2>&1) || {
            log_error "Failed to execute jq via Docker"
            log_error "  Docker jq error: $_jq_output"
            log_error "  Hint: Install jq locally for better compatibility:"
            log_error "    Ubuntu/Debian: sudo apt-get install jq"
            log_error "    RHEL/CentOS:   sudo yum install jq"
            return 1
        }
        printf '%s\n' "$_jq_output"
    fi
}

# curlチェック（必須）
if ! command -v curl > /dev/null 2>&1; then
    log_error "curl is required but not installed"
    echo "Please install curl first:"
    echo "  Ubuntu/Debian: sudo apt-get install curl"
    exit 1
fi

# Supervisorバージョン決定（GitHub Releaseから取得）
RELEASE_URL="https://github.com/AgenticSec/AgenticSec-Edge-Installer/releases/download/supervisor-latest/supervisor-version.txt"

log_info "Fetching latest supervisor version from GitHub Release..."
SUPERVISOR_VERSION=$(curl --max-time 30 -fsSL "$RELEASE_URL" 2>&1) || {
    log_error "Failed to fetch latest supervisor version"
    log_error "  URL: $RELEASE_URL"
    log_error "  Error: $(echo "$SUPERVISOR_VERSION" | head -1)"
    log_error "  Please check your internet connection"
    cleanup_on_error
    exit 1
}

if [ -z "$SUPERVISOR_VERSION" ]; then
    log_error "Failed to fetch latest supervisor version (empty response)"
    log_error "  Tried: $RELEASE_URL"
    log_error "  Please check your internet connection"
    cleanup_on_error
    exit 1
fi

log_info "Latest supervisor version: $SUPERVISOR_VERSION"

# Supervisorイメージを構築
SUPERVISOR_IMAGE="ghcr.io/agenticsec/agenticsec-supervisor:$SUPERVISOR_VERSION"
log_info "Supervisor image: $SUPERVISOR_IMAGE"

# Supervisorイメージをpull
log_info "Pulling supervisor image (this may take a moment)..."
PULL_OUTPUT=$(docker pull "$SUPERVISOR_IMAGE" 2>&1) || {
    log_error "Failed to pull supervisor image: $SUPERVISOR_IMAGE"
    log_error "  Docker error: $(echo "$PULL_OUTPUT" | tail -3)"
    log_error ""
    log_error "Please check:"
    log_error "  - Internet connection"
    log_error "  - Docker daemon is running: sudo systemctl status docker"
    log_error "  - The image tag '$SUPERVISOR_VERSION' exists"
    cleanup_on_error
    exit 1
}
log_info "✓ Image pulled successfully"

# 7. state.jsonのimage_tagを更新
log_info "Updating supervisor state with image tag..."
IMAGE_TAG="$SUPERVISOR_VERSION"  # バージョン文字列をそのまま使用（例: edge-v1.0.0）

# JSONファイルの更新（PLACEHOLDER → 実際のタグ）
if [ -f "$STATE_TEMPLATE" ]; then
    sed -e "s|{{IMAGE_TAG}}|$IMAGE_TAG|g" \
        -e "s|{{AGENTICSEC_CLOUD_API_KEY}}|$AGENTICSEC_API_KEY|g" \
        -e "s|{{AGENTICSEC_CLOUD_BASEURL}}|$AGENTICSEC_BASEURL|g" \
        "$STATE_TEMPLATE" > "$STATE_FILE"
    log_info "  Updated image tag: $IMAGE_TAG"
else
    log_error "Template not found: $STATE_TEMPLATE"
    cleanup_on_error
    exit 1
fi

# 7.5. アップグレードチェックスクリプトをインストール
log_info "Installing upgrade check script..."

UPGRADE_SCRIPT_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-supervisor-check-upgrade.sh"
UPGRADE_SCRIPT_TARGET="/usr/local/bin/agenticsec-supervisor-check-upgrade.sh"

if [ -f "$UPGRADE_SCRIPT_TEMPLATE" ]; then
    # スクリプトをコピー
    cp "$UPGRADE_SCRIPT_TEMPLATE" "$UPGRADE_SCRIPT_TARGET"
    # 実行権限を設定
    chmod 755 "$UPGRADE_SCRIPT_TARGET"
    log_info "  Installed upgrade check script: $UPGRADE_SCRIPT_TARGET"
else
    log_error "Upgrade check script template not found: $UPGRADE_SCRIPT_TEMPLATE"
    cleanup_on_error
    exit 1
fi

# 8. systemdサービスファイルをインストール
log_info "Installing systemd service..."

# systemctlの存在確認
if ! command -v systemctl > /dev/null 2>&1; then
    log_error "systemctl is not available"
    echo ""
    echo "This installer requires systemd."
    echo "For non-systemd systems, manual installation is required."
    exit 1
fi

# サービステンプレートファイルの場所を探す
SCRIPT_DIR=$(dirname "$0")
SERVICE_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-supervisor.service.template"

if [ ! -f "$SERVICE_TEMPLATE" ]; then
    log_error "Service template not found at $SERVICE_TEMPLATE"
    cleanup_on_error
    exit 1
fi

# jq コマンドを決定
if command -v jq > /dev/null 2>&1; then
    JQ_COMMAND="jq"
else
    JQ_COMMAND="docker run --rm -i imega/jq"
fi

# テンプレートから生成
sed -e "s|{{DOCKER_BIN}}|$DOCKER_BIN|g" \
    -e "s|{{DOCKER_SOCK}}|$DOCKER_SOCK|g" \
    -e "s|{{JQ_COMMAND}}|$JQ_COMMAND|g" \
    "$SERVICE_TEMPLATE" > /etc/systemd/system/agenticsec-supervisor.service
log_info "  Created service file at /etc/systemd/system/agenticsec-supervisor.service"
log_info "  Using Docker binary: $DOCKER_BIN"
log_info "  Using Docker socket: $DOCKER_SOCK"
log_info "  Using jq command: $JQ_COMMAND"

# systemdをリロード
systemctl daemon-reload
log_info "  Reloaded systemd daemon"

# サービスを有効化（自動起動）
systemctl enable agenticsec-supervisor
log_info "  Enabled agenticsec-supervisor service (auto-start on boot)"

# サービスを起動
systemctl start agenticsec-supervisor
log_info "  Started agenticsec-supervisor service"

# 9. Observability設定（Fluent Bit setup）
log_info "Setting up observability (Fluent Bit for log collection)..."

# 9.1 Observability設定ディレクトリ作成
OBSERVABILITY_DIR="/etc/agenticsec/edge-observability"
if [ ! -d "$OBSERVABILITY_DIR" ]; then
    mkdir -p "$OBSERVABILITY_DIR"
    chmod 700 "$OBSERVABILITY_DIR"
    log_info "  Created $OBSERVABILITY_DIR/"
else
    log_info "  $OBSERVABILITY_DIR/ already exists"
fi

# 9.2 Hub APIからObservability設定取得
log_info "Fetching observability configuration from AgenticSec Hub..."

# Edge API Keyはstate.jsonから取得（既存のAGENTICSEC_CLOUD_API_KEYを流用）
# NOTE: パイプ経由で渡す（Docker版jqはホストのファイルパスを読めないため）
EDGE_API_KEY=$(cat "$STATE_FILE" | jq_exec -r '.agenticsec_cloud_api_key') || {
    log_error "Failed to read API key from state file: $STATE_FILE"
    log_error "  Please check if the file exists and contains valid JSON"
    cleanup_on_error
    exit 1
}

if [ -z "$EDGE_API_KEY" ] || [ "$EDGE_API_KEY" = "null" ]; then
    log_error "API key is empty or null in state file: $STATE_FILE"
    log_error "  Please re-run the installer and provide a valid API key"
    cleanup_on_error
    exit 1
fi

# Base URLからObservability APIエンドポイントを構築
# 例: https://api.agenticsec.tech/api/edge/supervisor → https://api.agenticsec.tech/api/edge/installer/v1/observability
OBSERVABILITY_API_URL=$(echo "$AGENTICSEC_BASEURL" | sed 's|/api/edge/supervisor|/api/edge/installer/v1/observability|')

# curlエラーをキャッチ（set -e でスクリプトが終了しないように）
OBSERVABILITY_RESPONSE=$(curl --max-time 30 -fsSL \
    -H "X-API-Key: $EDGE_API_KEY" \
    "$OBSERVABILITY_API_URL" 2>&1) || {
    log_error "Failed to fetch observability configuration from Hub"
    log_error "  API URL: $OBSERVABILITY_API_URL"
    log_error "  Error: $(echo "$OBSERVABILITY_RESPONSE" | head -1)"
    log_error ""
    log_error "The Hub API endpoint '/api/edge/installer/v1/observability' is required."
    log_error "Please ensure the Hub is running the latest version that supports this endpoint."
    cleanup_on_error
    exit 1
}

if [ -z "$OBSERVABILITY_RESPONSE" ]; then
    log_error "Empty response from Hub observability API"
    log_error "  API URL: $OBSERVABILITY_API_URL"
    log_error "  Please check the Hub API is running and accessible."
    cleanup_on_error
    exit 1
else
    # レスポンスが有効なJSONか確認
    if echo "$OBSERVABILITY_RESPONSE" | jq_exec -e . > /dev/null 2>&1; then
        # 必須フィールド確認
        LOKI_ENDPOINT=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.log_endpoint // empty') || {
            log_error "Failed to parse log_endpoint from observability response"
            cleanup_on_error
            exit 1
        }

        if [ -z "$LOKI_ENDPOINT" ]; then
            log_error "Invalid observability configuration received (missing log_endpoint)"
            log_error "  Please check the Hub API configuration."
            cleanup_on_error
            exit 1
        else
            # 9.3 レスポンスJSONをそのまま保存
            echo "$OBSERVABILITY_RESPONSE" > "$OBSERVABILITY_DIR/api-config.json"
            chmod 600 "$OBSERVABILITY_DIR/api-config.json"
            log_info "  Saved observability configuration to $OBSERVABILITY_DIR/api-config.json"

            # 9.4 Fluent Bit設定ファイル生成
            LOKI_HOST=$(echo "$LOKI_ENDPOINT" | sed -E 's|https?://([^/]+).*|\1|')
            LOKI_USER_ID=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.log_user_id') || {
                log_error "Failed to parse log_user_id from observability response"
                cleanup_on_error
                exit 1
            }
            LOKI_API_TOKEN=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.log_api_token') || {
                log_error "Failed to parse log_api_token from observability response"
                cleanup_on_error
                exit 1
            }
            ENV_NAME=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.env') || {
                log_error "Failed to parse env from observability response"
                cleanup_on_error
                exit 1
            }

            if [ -z "$LOKI_HOST" ] || [ -z "$LOKI_USER_ID" ] || [ "$LOKI_USER_ID" = "null" ] || [ -z "$LOKI_API_TOKEN" ] || [ "$LOKI_API_TOKEN" = "null" ] || [ -z "$ENV_NAME" ] || [ "$ENV_NAME" = "null" ]; then
                log_error "Incomplete observability configuration received from Hub"
                log_error "  log_endpoint host: ${LOKI_HOST:-<empty>}"
                log_error "  log_user_id: ${LOKI_USER_ID:-<empty>}"
                log_error "  log_api_token: $(if [ -n "$LOKI_API_TOKEN" ] && [ "$LOKI_API_TOKEN" != "null" ]; then echo '<set>'; else echo '<empty>'; fi)"
                log_error "  env: ${ENV_NAME:-<empty>}"
                log_error "  Please check the Hub observability configuration."
                cleanup_on_error
                exit 1
            fi

            FLUENT_BIT_CONFIG_TEMPLATE="$SCRIPT_DIR/templates/fluent-bit.conf.template"
            if [ -f "$FLUENT_BIT_CONFIG_TEMPLATE" ]; then
                sed -e "s|{{LOKI_ENDPOINT_HOST}}|$LOKI_HOST|g" \
                    -e "s|{{LOKI_USER_ID}}|$LOKI_USER_ID|g" \
                    -e "s|{{LOKI_API_TOKEN}}|$LOKI_API_TOKEN|g" \
                    -e "s|{{SUPERVISOR_ID}}|$SUPERVISOR_ID_CANDIDATE|g" \
                    -e "s|{{ENV}}|$ENV_NAME|g" \
                    "$FLUENT_BIT_CONFIG_TEMPLATE" > "$OBSERVABILITY_DIR/fluent-bit.conf"
                chmod 644 "$OBSERVABILITY_DIR/fluent-bit.conf"
                log_info "  Created Fluent Bit configuration: $OBSERVABILITY_DIR/fluent-bit.conf"
            else
                log_error "Template not found: $FLUENT_BIT_CONFIG_TEMPLATE"
                cleanup_on_error
                exit 1
            fi

            # 9.4b Cloud-side Log Ingestor (Phase 4) — render optional ingestor.conf
            #
            # Hub `/api/edge/installer/v1/observability` may return
            # `log_ingest_endpoint` and `log_ingest_api_token` once Phase 1/2/3
            # are complete for this org. Both fields are optional and Hub drops
            # them as a pair, so we only generate the ingestor block when both
            # are present. Otherwise we write an empty placeholder so the
            # `@INCLUDE` in fluent-bit.conf still resolves.
            #
            # Auth contract (Notion #744 + PR #1495 / #1496 / #1497):
            # Cloud-side aggregator is fronted by the existing Hub API Gateway,
            # which performs native API Key authentication. Edge sends the
            # `{org_id}_{32-hex}` token verbatim in the `x-api-key` header;
            # API Gateway VTL strips the trailing 33 chars to inject `org_id`
            # server-side. No client-side hashing required.
            #
            # `log_ingest_endpoint` is a URI path (e.g. `/api/v1/edge-logs`).
            # The host is reused from AGENTICSEC_BASEURL so Edge keeps a
            # single trust anchor (the Hub API host).
            LOG_INGEST_ENDPOINT=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.log_ingest_endpoint // empty') || LOG_INGEST_ENDPOINT=""
            LOG_INGEST_API_TOKEN=$(echo "$OBSERVABILITY_RESPONSE" | jq_exec -r '.log_ingest_api_token // empty') || LOG_INGEST_API_TOKEN=""
            INGESTOR_CONF_TEMPLATE="$SCRIPT_DIR/templates/ingestor.conf.template"
            INGESTOR_CONF_TARGET="$OBSERVABILITY_DIR/ingestor.conf"

            if [ -n "$LOG_INGEST_ENDPOINT" ] && [ "$LOG_INGEST_ENDPOINT" != "null" ] \
               && [ -n "$LOG_INGEST_API_TOKEN" ] && [ "$LOG_INGEST_API_TOKEN" != "null" ]; then
                if [ ! -f "$INGESTOR_CONF_TEMPLATE" ]; then
                    log_error "Template not found: $INGESTOR_CONF_TEMPLATE"
                    cleanup_on_error
                    exit 1
                fi

                LOG_INGEST_HOST=$(echo "$AGENTICSEC_BASEURL" | sed -E 's|https?://([^/]+).*|\1|')
                if [ -z "$LOG_INGEST_HOST" ]; then
                    log_error "Could not parse host from AGENTICSEC_BASEURL: $AGENTICSEC_BASEURL"
                    cleanup_on_error
                    exit 1
                fi

                # sed delimiter `|` is safe here: host is a DNS name, URI is
                # a URL path (starts with `/`), env / token are unlikely to
                # contain `|`.
                sed -e "s|{{ENV}}|$ENV_NAME|g" \
                    -e "s|{{LOG_INGEST_HOST}}|$LOG_INGEST_HOST|g" \
                    -e "s|{{LOG_INGEST_URI}}|$LOG_INGEST_ENDPOINT|g" \
                    -e "s|{{LOG_INGEST_API_TOKEN}}|$LOG_INGEST_API_TOKEN|g" \
                    "$INGESTOR_CONF_TEMPLATE" > "$INGESTOR_CONF_TARGET"
                chmod 600 "$INGESTOR_CONF_TARGET"
                log_info "  Created Log Ingestor configuration: $INGESTOR_CONF_TARGET (host: $LOG_INGEST_HOST, uri: $LOG_INGEST_ENDPOINT)"
            else
                # Empty placeholder so the @INCLUDE in fluent-bit.conf resolves.
                cat > "$INGESTOR_CONF_TARGET" <<'INGESTOR_CONF_EOF'
# Log Ingestor not configured for this organization yet — Hub returned no
# log_ingest_endpoint / log_ingest_api_token. Re-run the installer after
# Phase 4 rollout for this org to enable the dual-output sink.
INGESTOR_CONF_EOF
                chmod 644 "$INGESTOR_CONF_TARGET"
                log_info "  Log Ingestor not configured (Hub returned no log_ingest_endpoint); wrote empty placeholder"
            fi

            # 9.5 Fluent Bit systemd サービスインストール
            FLUENT_BIT_SERVICE_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-fluent-bit.service.template"
            if [ -f "$FLUENT_BIT_SERVICE_TEMPLATE" ]; then
                sed -e "s|{{DOCKER_BIN}}|$DOCKER_BIN|g" \
                    "$FLUENT_BIT_SERVICE_TEMPLATE" > /etc/systemd/system/agenticsec-fluent-bit.service
                log_info "  Created service file at /etc/systemd/system/agenticsec-fluent-bit.service"

                # systemdをリロード
                systemctl daemon-reload
                log_info "  Reloaded systemd daemon"

                # サービスを有効化（自動起動）
                systemctl enable agenticsec-fluent-bit
                log_info "  Enabled agenticsec-fluent-bit service (auto-start on boot)"

                # Fluent Bitイメージをpull
                log_info "Pulling Fluent Bit image..."
                FB_PULL_OUTPUT=$(docker pull fluent/fluent-bit:latest 2>&1) || {
                    log_warn "Failed to pull Fluent Bit image"
                    log_warn "  Docker error: $(echo "$FB_PULL_OUTPUT" | tail -2)"
                    log_warn "  Service will attempt to pull on first start"
                }
                if docker image inspect fluent/fluent-bit:latest > /dev/null 2>&1; then
                    log_info "  ✓ Fluent Bit image ready"
                fi

                # サービスを起動
                systemctl start agenticsec-fluent-bit
                log_info "  Started agenticsec-fluent-bit service"
                log_info "  ✓ Observability setup completed"
            else
                log_error "Template not found: $FLUENT_BIT_SERVICE_TEMPLATE"
                cleanup_on_error
                exit 1
            fi
        fi
    else
        log_error "Received invalid JSON response from Hub API"
        log_error "  Please check the Hub API configuration."
        cleanup_on_error
        exit 1
    fi
fi

# 10. ログクリーンアップ（日次ローテーション + 7日保持）
log_info "Installing log cleanup timer..."

LOG_CLEANUP_SCRIPT_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-log-cleanup.sh"
LOG_CLEANUP_SERVICE_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-log-cleanup.service.template"
LOG_CLEANUP_TIMER_TEMPLATE="$SCRIPT_DIR/templates/agenticsec-log-cleanup.timer.template"
LOG_CLEANUP_SCRIPT_TARGET="/usr/local/bin/agenticsec-log-cleanup.sh"

if [ -f "$LOG_CLEANUP_SCRIPT_TEMPLATE" ] && [ -f "$LOG_CLEANUP_SERVICE_TEMPLATE" ] && [ -f "$LOG_CLEANUP_TIMER_TEMPLATE" ]; then
    # Install cleanup script
    cp "$LOG_CLEANUP_SCRIPT_TEMPLATE" "$LOG_CLEANUP_SCRIPT_TARGET"
    chmod 755 "$LOG_CLEANUP_SCRIPT_TARGET"
    log_info "  Installed cleanup script: $LOG_CLEANUP_SCRIPT_TARGET"

    # Install systemd service (no template variables to substitute)
    cp "$LOG_CLEANUP_SERVICE_TEMPLATE" /etc/systemd/system/agenticsec-log-cleanup.service
    log_info "  Created service file at /etc/systemd/system/agenticsec-log-cleanup.service"

    # Install systemd timer (no template variables to substitute)
    cp "$LOG_CLEANUP_TIMER_TEMPLATE" /etc/systemd/system/agenticsec-log-cleanup.timer
    log_info "  Created timer file at /etc/systemd/system/agenticsec-log-cleanup.timer"

    # Reload systemd and enable timer
    systemctl daemon-reload
    systemctl enable --now agenticsec-log-cleanup.timer
    log_info "  Enabled and started agenticsec-log-cleanup.timer (daily)"
    log_info "  ✓ Log cleanup setup completed"
else
    log_warn "Log cleanup templates not found (skipping)"
    log_warn "  Expected: $LOG_CLEANUP_SCRIPT_TEMPLATE"
    log_warn "  Expected: $LOG_CLEANUP_SERVICE_TEMPLATE"
    log_warn "  Expected: $LOG_CLEANUP_TIMER_TEMPLATE"
fi

# 11. アンインストーラーをシステムに配置
log_info "Installing uninstall command..."

UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall.sh"
UNINSTALL_TARGET="/usr/bin/agenticsec-uninstall"

if [ -f "$UNINSTALL_SCRIPT" ]; then
    # アンインストーラーをコピー
    cp "$UNINSTALL_SCRIPT" "$UNINSTALL_TARGET"
    # 実行権限を設定
    chmod 755 "$UNINSTALL_TARGET"
    log_info "  Installed uninstall command: agenticsec-uninstall"
else
    log_warn "Uninstall script not found at $UNINSTALL_SCRIPT"
    log_warn "Skipping uninstall command installation"
fi

# 12. 完了メッセージ
echo ""
echo "==========================================="
log_info "Installation completed successfully!"
echo "==========================================="
echo ""
echo "Services are now running!"
echo ""
echo "Useful commands:"
echo "  Supervisor:"
echo "    Check status: sudo systemctl status agenticsec-supervisor"
echo "    View logs:    sudo journalctl -u agenticsec-supervisor -f"
echo "    Stop:         sudo systemctl stop agenticsec-supervisor"
echo "    Restart:      sudo systemctl restart agenticsec-supervisor"
echo ""
echo "  Fluent Bit (Log Collection):"
echo "    Check status: sudo systemctl status agenticsec-fluent-bit"
echo "    View logs:    sudo journalctl -u agenticsec-fluent-bit -f"
echo "    Stop:         sudo systemctl stop agenticsec-fluent-bit"
echo "    Restart:      sudo systemctl restart agenticsec-fluent-bit"
echo ""
echo "  Log Cleanup (daily timer):"
echo "    Check timer:  sudo systemctl list-timers agenticsec-log-cleanup.timer"
echo "    Run manually: sudo systemctl start agenticsec-log-cleanup.service"
echo "    View logs:    sudo journalctl -u agenticsec-log-cleanup.service"
echo ""
echo "  Uninstall:    sudo agenticsec-uninstall"