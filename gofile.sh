#!/bin/bash

# ─────────────────────────────────────────
# gofile — Upload file(s) to GoFile
# Usage: gofile file1 [file2 ...]
# ─────────────────────────────────────────

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_err()   { echo -e "${RED}[x]${NC} $*" >&2; }
die()       { log_err "$*"; exit 1; }

# ── Dependency check ──────────────────────
for dep in curl jq; do
    command -v "$dep" &>/dev/null || die "Missing dependency: $dep"
done

# ── Argument check ────────────────────────
[[ "$#" -eq 0 ]] && die "No file specified. Usage: $0 <file> [file2 ...]"

# ── Get best server ───────────────────────
get_server() {
    local response
    response=$(curl -sf --max-time 10 "https://api.gofile.io/servers") \
        || die "Failed to reach GoFile API. Check your connection."

    local server
    server=$(echo "$response" | jq -r '.data.servers[0].name // empty')
    [[ -z "$server" ]] && die "Could not determine upload server from API response."
    echo "$server"
}

# ── Upload single file ────────────────────
upload_file() {
    local file="$1"
    local server="$2"

    [[ -f "$file" ]] || { log_err "File not found: $file"; return 1; }
    [[ -r "$file" ]] || { log_err "File not readable: $file"; return 1; }

    local size
    size=$(du -sh "$file" 2>/dev/null | cut -f1)
    log_info "Uploading: ${BOLD}$(basename "$file")${NC} (${size})"

    local response
    response=$(curl -# \
        --max-time 300 \
        --retry 2 \
        --retry-delay 3 \
        -F "file=@${file}" \
        "https://${server}.gofile.io/uploadFile" 2>/dev/tty)

    local status link
    status=$(echo "$response" | jq -r '.status // empty')
    link=$(echo "$response" | jq -r '.data.downloadPage // empty')

    if [[ "$status" != "ok" || -z "$link" ]]; then
        log_err "Unexpected API response for: $file"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi

    log_ok "${BOLD}$(basename "$file")${NC}"
    log_ok "${GREEN}${link}${NC}"
}

# ── Main ──────────────────────────────────
main() {
    log_info "Fetching best GoFile server..."
    local server
    server=$(get_server)
    log_ok "Server: ${BOLD}${server}${NC}"
    echo

    local success=0 fail=0

    for file in "$@"; do
        if upload_file "$file" "$server"; then
            ((success++)) || true
        else
            ((fail++)) || true
        fi
        echo
    done

    if [[ $(( success + fail )) -gt 1 ]]; then
        echo -e "${BOLD}─── Summary ───────────────────────${NC}"
        [[ $success -gt 0 ]] && log_ok "$success file(s) uploaded successfully."
        [[ $fail -gt 0 ]]    && log_warn "$fail file(s) failed."
    fi

    [[ $fail -gt 0 ]] && exit 1
    exit 0
}

main "$@"
