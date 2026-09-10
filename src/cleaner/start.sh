#!/system/bin/sh

START_VERSION="1.0"

# 脚本自身所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="."

SCRIPT_PATH="${SCRIPT_DIR}/clean.sh"
CONFIG_DIR="${SCRIPT_DIR}/.cleaner"
LOG_DIR="${CONFIG_DIR}/logs"
TEMP_DIR="${CONFIG_DIR}/temp"
BACKUP_DIR="${CONFIG_DIR}/backup"

UPDATE_SERVER="https://leekingx.cn/cleaner"
VERSION_URL="${UPDATE_SERVER}/version.txt"
HASH_URL="${UPDATE_SERVER}/clean.sh.sha256"
SCRIPT_URL="${UPDATE_SERVER}/clean.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

DRY_RUN="false"
FORCE_UPDATE="false"

init_dirs() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR" "$BACKUP_DIR" 2>/dev/null
}

log_ok()   { echo "  ${GREEN}[OK]${NC} $1"; }
log_warn() { echo "  ${YELLOW}[WARN]${NC} $1"; }
log_info() { echo "  ${BLUE}[INFO]${NC} $1"; }
log_fail() { echo "  ${RED}[FAIL]${NC} $1"; }

log_phase() {
    echo ""
    echo "${BOLD}${CYAN}>>> $1${NC}"
    echo "${GRAY}------------------------------------------------------------${NC}"
}

download_file() {
    local url="$1"
    local output="$2"
    rm -f "$output" 2>/dev/null
    if command -v curl >/dev/null 2>&1; then
        curl -L -s -m 10 -o "$output" "$url" 2>/dev/null
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 10 -O "$output" "$url" 2>/dev/null
        return $?
    else
        return 1
    fi
}

calc_hash() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
        return 0
    fi
    if command -v busybox >/dev/null 2>&1; then
        busybox sha256sum "$file" 2>/dev/null | awk '{print $1}'
        return 0
    fi
    if command -v toybox >/dev/null 2>&1; then
        toybox sha256sum "$file" 2>/dev/null | awk '{print $1}'
        return 0
    fi
    echo ""
    return 1
}

local_clean_version() {
    if [ -f "$SCRIPT_PATH" ]; then
        grep -m1 '^SCRIPT_VERSION=' "$SCRIPT_PATH" 2>/dev/null | cut -d'"' -f2
    fi
}

fetch_remote_version() {
    local out="${TEMP_DIR}/version.txt"
    if ! download_file "$VERSION_URL" "$out"; then
        return 1
    fi
    head -n 1 "$out" 2>/dev/null | tr -d '\r\n'
}

fetch_remote_hash() {
    local out="${TEMP_DIR}/clean.sh.sha256"
    if ! download_file "$HASH_URL" "$out"; then
        return 1
    fi
    awk '{print $1}' "$out" 2>/dev/null | head -n 1 | tr -d '\r\n'
}

update_clean() {
    log_phase "Checking clean.sh Update"

    local remote_version
    remote_version=$(fetch_remote_version)
    if [ -z "$remote_version" ]; then
        log_warn "Update server unreachable, using local clean.sh"
        return 1
    fi

    local local_version
    local_version=$(local_clean_version)
    [ -z "$local_version" ] && local_version="none"

    log_info "Local  clean.sh: v${local_version}"
    log_info "Remote clean.sh: v${remote_version}"

    if [ "$remote_version" = "$local_version" ] && [ "$FORCE_UPDATE" != "true" ]; then
        log_ok "clean.sh already up to date"
        return 0
    fi

    log_warn "New version found, downloading..."

    local remote_hash
    remote_hash=$(fetch_remote_hash)
    if [ -z "$remote_hash" ]; then
        log_fail "Cannot fetch remote hash, abort update"
        return 1
    fi
    log_info "Remote hash: $remote_hash"

    # 下载到缓存文件
    local tmp_script="${TEMP_DIR}/clean.sh.download"
    if ! download_file "$SCRIPT_URL" "$tmp_script"; then
        log_fail "Download failed"
        rm -f "$tmp_script" 2>/dev/null
        return 1
    fi

    if [ ! -s "$tmp_script" ]; then
        log_fail "Downloaded file is empty"
        rm -f "$tmp_script" 2>/dev/null
        return 1
    fi

    if ! head -n 1 "$tmp_script" 2>/dev/null | grep -q '^#!'; then
        log_fail "Downloaded file is not a valid script"
        rm -f "$tmp_script" 2>/dev/null
        return 1
    fi

    local local_hash
    local_hash=$(calc_hash "$tmp_script")
    if [ -z "$local_hash" ]; then
        log_fail "No hash tool available (sha256sum/busybox/toybox)"
        rm -f "$tmp_script" 2>/dev/null
        return 1
    fi
    log_info "Local  hash: $local_hash"

    if [ "$local_hash" != "$remote_hash" ]; then
        log_fail "Hash mismatch, abort update"
        rm -f "$tmp_script" 2>/dev/null
        return 1
    fi
    log_ok "Hash verified"

    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] would install clean.sh v${remote_version}"
        rm -f "$tmp_script" 2>/dev/null
        return 0
    fi

    if [ -f "$SCRIPT_PATH" ]; then
        cp "$SCRIPT_PATH" "${BACKUP_DIR}/clean_$(date +%Y%m%d_%H%M%S).sh" 2>/dev/null
    fi

    sed -i "s/^SCRIPT_VERSION=\"[^\"]*\"/SCRIPT_VERSION=\"$remote_version\"/" "$tmp_script" 2>/dev/null

    chmod 755 "$tmp_script" 2>/dev/null
    mv -f "$tmp_script" "$SCRIPT_PATH" 2>/dev/null

    if [ ! -f "$SCRIPT_PATH" ]; then
        log_fail "Install failed"
        return 1
    fi

    log_ok "Installed clean.sh v${remote_version}"
    return 0
}

launch_clean() {
    if [ ! -f "$SCRIPT_PATH" ]; then
        log_fail "clean.sh not found: $SCRIPT_PATH"
        return 1
    fi
    log_phase "Launching clean.sh"
    sh "$SCRIPT_PATH" "$@"
    return $?
}

main() {
    init_dirs

    local clean_args=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                echo "Usage: sh start.sh [--dry-run] [--force-update]"
                return 0
                ;;
            --dry-run)
                DRY_RUN="true"; clean_args="$clean_args --dry-run"; shift ;;
            --force-update)
                FORCE_UPDATE="true"; shift ;;
            *)
                clean_args="$clean_args $1"; shift ;;
        esac
    done

    echo ""
    echo "${BOLD}${WHITE} MonStarsh Cleaner Launcher v${START_VERSION}${NC}"
    echo "${GRAY} $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo "${GRAY} Dir: $SCRIPT_DIR${NC}"

    update_clean

    if [ ! -f "$SCRIPT_PATH" ]; then
        log_fail "No clean.sh available, exit"
        return 1
    fi

    launch_clean $clean_args
}

main "$@"