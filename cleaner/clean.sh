#!/system/bin/sh

SCRIPT_VERSION="5.1"

# 脚本自身所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
[ -z "$SCRIPT_DIR" ] && SCRIPT_DIR="."

CONFIG_DIR="${SCRIPT_DIR}/.cleaner"
LOG_DIR="${CONFIG_DIR}/logs"
TEMP_DIR="${CONFIG_DIR}/temp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_DELETED=0
TOTAL_FREED_MB=0
TOTAL_SCANNED=0
START_TIME=$(date +%s)
DRY_RUN="false"

init_dirs() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR" 2>/dev/null
}

log_phase() {
    echo ""
    echo "${BOLD}${CYAN}>>> $1${NC}"
    echo "${GRAY}------------------------------------------------------------${NC}"
}

log_ok()   { echo "  ${GREEN}[OK]${NC} $1"; }
log_warn() { echo "  ${YELLOW}[WARN]${NC} $1"; }
log_info() { echo "  ${BLUE}[INFO]${NC} $1"; }
log_fail() { echo "  ${RED}[FAIL]${NC} $1"; }

log_stat() {
    printf "  ${WHITE}%-16s${NC} ${CYAN}%s${NC}\n" "$1:" "$2"
}

show_banner() {
    clear 2>/dev/null
    echo ""
    echo "${BOLD}${CYAN}   ███╗   ███╗ ██████╗ ███╗   ██╗███████╗████████╗ █████╗ ██████╗ ███████╗${NC}"
    echo "${BOLD}${CYAN}   ████╗ ████║██╔═══██╗████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝${NC}"
    echo "${BOLD}${CYAN}   ██╔████╔██║██║   ██║██╔██╗ ██║███████╗   ██║   ███████║██████╔╝███████╗${NC}"
    echo "${BOLD}${CYAN}   ██║╚██╔╝██║██║   ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██╔══██╗╚════██║${NC}"
    echo "${BOLD}${CYAN}   ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████║   ██║   ██║  ██║██║  ██║███████║${NC}"
    echo "${BOLD}${CYAN}   ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝${NC}"
    echo ""
    echo "${BOLD}${WHITE}    MonStarsh Cache Cleaner v${SCRIPT_VERSION}${NC}"
    echo "${GRAY}    Start  : $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo "${GRAY}    Dir    : $SCRIPT_DIR${NC}"
    echo "${GRAY}    Mode   : $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN" || echo "EXECUTE")${NC}"
    echo "${GRAY}------------------------------------------------------------${NC}"
    echo ""
}

get_size_mb() {
    local path="$1"
    if [ -d "$path" ]; then
        du -sm "$path" 2>/dev/null | cut -f1 | sed 's/[^0-9]//g'
    else
        echo "0"
    fi
}

get_file_count() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

format_size() {
    local size_mb="$1"
    if [ "$size_mb" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $size_mb/1024}") GB"
    else
        echo "${size_mb} MB"
    fi
}

delete_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        return 0
    fi

    local size=$(du -k "$file" 2>/dev/null | cut -f1 | tr -d ' ')
    local size_mb=$((size / 1024))

    if [ "$DRY_RUN" = "true" ]; then
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_FREED_MB=$((TOTAL_FREED_MB + size_mb))
        return 0
    fi

    rm -f "$file" 2>/dev/null
    if [ $? -eq 0 ]; then
        TOTAL_DELETED=$((TOTAL_DELETED + 1))
        TOTAL_FREED_MB=$((TOTAL_FREED_MB + size_mb))
    fi
}

clean_cache_dir_deep() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return 0
    fi

    local size_before=$(get_size_mb "$dir")
    local count_before=$(get_file_count "$dir")
    TOTAL_SCANNED=$((TOTAL_SCANNED + count_before))

    if [ "$DRY_RUN" = "true" ]; then
        TOTAL_DELETED=$((TOTAL_DELETED + count_before))
        TOTAL_FREED_MB=$((TOTAL_FREED_MB + size_before))
        if [ "$count_before" -gt 0 ]; then
            log_info "[DRY-RUN] would delete: $count_before files, $(format_size $size_before) from $dir"
        fi
        return 0
    fi

    rm -rf "$dir"/* 2>/dev/null
    local remaining=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
    local deleted=$((count_before - remaining))

    if [ ! "$(ls -A "$dir" 2>/dev/null)" ]; then
        rmdir "$dir" 2>/dev/null
    fi

    local size_after=$(get_size_mb "$dir")
    local freed=$((size_before - size_after))
    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_FREED_MB=$((TOTAL_FREED_MB + freed))

    if [ "$deleted" -gt 0 ] || [ "$freed" -gt 0 ]; then
        log_ok "cleaned: $deleted files, $(format_size $freed) from ${dir##*/}"
    fi
}

clean_all_caches() {
    log_phase "Cleaning All Cache Files"

    log_info "Cleaning common cache directories..."

    if [ -d "${SCRIPT_DIR}/DCIM/.thumbnails" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/DCIM/.thumbnails"; fi
    if [ -d "${SCRIPT_DIR}/DCIM/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/DCIM/.cache"; fi
    if [ -d "${SCRIPT_DIR}/Pictures/.thumbnails" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Pictures/.thumbnails"; fi
    if [ -d "${SCRIPT_DIR}/Pictures/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Pictures/.cache"; fi
    if [ -d "${SCRIPT_DIR}/Music/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Music/.cache"; fi
    if [ -d "${SCRIPT_DIR}/Movies/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Movies/.cache"; fi
    if [ -d "${SCRIPT_DIR}/Download/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Download/.cache"; fi
    if [ -d "${SCRIPT_DIR}/Documents/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/Documents/.cache"; fi
    if [ -d "${SCRIPT_DIR}/.cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.cache"; fi
    if [ -d "${SCRIPT_DIR}/.thumbnails" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.thumbnails"; fi
    if [ -d "${SCRIPT_DIR}/.temp" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.temp"; fi
    if [ -d "${SCRIPT_DIR}/.tmp" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.tmp"; fi
    if [ -d "${SCRIPT_DIR}/.trash" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.trash"; fi
    if [ -d "${SCRIPT_DIR}/.recycle" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.recycle"; fi
    if [ -d "${SCRIPT_DIR}/temp" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/temp"; fi
    if [ -d "${SCRIPT_DIR}/tmp" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/tmp"; fi
    if [ -d "${SCRIPT_DIR}/cache" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/cache"; fi
    if [ -d "${SCRIPT_DIR}/.Trash" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/.Trash"; fi
    if [ -d "${SCRIPT_DIR}/trash" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/trash"; fi
    if [ -d "${SCRIPT_DIR}/DCIM/thumbnails" ]; then clean_cache_dir_deep "${SCRIPT_DIR}/DCIM/thumbnails"; fi

    if [ -d "${SCRIPT_DIR}/Android/data" ]; then
        log_info "Cleaning Android app caches..."
        find "${SCRIPT_DIR}/Android/data" -type d \( -name "cache" -o -name "Cache" -o -name "tmp" -o -name "Tmp" -o -name "temp" -o -name "Temp" -o -name ".cache" -o -name ".tmp" -o -name ".temp" -o -name "caches" -o -name "Caches" -o -name "logs" -o -name "Logs" \) 2>/dev/null | while read -r cache_dir; do
            clean_cache_dir_deep "$cache_dir"
        done
    fi

    log_info "Cleaning temp files..."
    find "$SCRIPT_DIR" -type f \( -name "*.tmp" -o -name "*.TMP" -o -name "*.temp" -o -name "*.TEMP" -o -name "*.cache" -o -name "*.CACHE" -o -name "*.log" -o -name "*.LOG" -o -name "*.bak" -o -name "*.BAK" -o -name "*.backup" -o -name "*.lock" -o -name "*.LOCK" -o -name "*.pid" -o -name "*.PID" -o -name "*.swp" -o -name "*~" -o -name "*.tempfile" -o -name "*.tmpfile" \) 2>/dev/null | grep -v "^${CONFIG_DIR}/" | while read -r file; do
        delete_file "$file"
    done

    log_info "Cleaning cache directories..."
    find "$SCRIPT_DIR" -type d \( -name "cache" -o -name "Cache" -o -name "tmp" -o -name "Tmp" -o -name "temp" -o -name "Temp" -o -name ".cache" -o -name ".tmp" -o -name ".temp" -o -name "caches" -o -name "Caches" -o -name "logs" -o -name "Logs" -o -name "thumbnails" -o -name "Thumbnails" -o -name ".thumbnails" \) 2>/dev/null | grep -v "^${CONFIG_DIR}/" | grep -v "^${SCRIPT_DIR}/Android/data/[^/]*/lib/" | grep -v "^${SCRIPT_DIR}/Android/obb/" | while read -r dir; do
        clean_cache_dir_deep "$dir"
    done

    log_info "Cleaning empty directories..."
    find "$SCRIPT_DIR" -type d -empty 2>/dev/null | grep -v "^${CONFIG_DIR}/" | while read -r empty_dir; do
        if [ "$DRY_RUN" = "true" ]; then
            TOTAL_DELETED=$((TOTAL_DELETED + 1))
        else
            rmdir "$empty_dir" 2>/dev/null
        fi
    done
}

show_report() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    echo ""
    log_phase "Report"
    log_stat "Scanned" "$TOTAL_SCANNED files"
    log_stat "Deleted" "$TOTAL_DELETED files"
    log_stat "Freed" "$(format_size $TOTAL_FREED_MB)"
    log_stat "Elapsed" "${elapsed}s"
    if [ "$DRY_RUN" = "true" ]; then
        echo ""
        log_warn "DRY-RUN mode, nothing deleted"
    fi
    echo ""
    log_ok "Done"
}

save_log() {
    local log_file="${LOG_DIR}/clean_$(date +%Y%m%d_%H%M%S).log"
    {
        echo "=== MonStarsh Cache Cleaner Log ==="
        echo "Time   : $(date)"
        echo "Dir    : $SCRIPT_DIR"
        echo "Mode   : $([ "$DRY_RUN" = "true" ] && echo "DRY-RUN" || echo "EXECUTE")"
        echo "Scanned: $TOTAL_SCANNED"
        echo "Deleted: $TOTAL_DELETED"
        echo "Freed  : $TOTAL_FREED_MB MB"
        echo "Elapsed: $(($(date +%s) - START_TIME))s"
    } > "$log_file"
    log_info "Log saved: $log_file"
}

main() {
    init_dirs
    while [ $# -gt 0 ]; do
        case "$1" in
            --help) echo "Usage: sh clean.sh [--dry-run]"; return 0 ;;
            --dry-run) DRY_RUN="true"; shift ;;
            *) echo "Unknown: $1"; return 1 ;;
        esac
    done
    show_banner
    clean_all_caches
    show_report
    save_log
    if [ "$DRY_RUN" = "true" ]; then
        echo ""
        log_warn "Remove --dry-run to execute for real"
    fi
    echo ""
}

main "$@"