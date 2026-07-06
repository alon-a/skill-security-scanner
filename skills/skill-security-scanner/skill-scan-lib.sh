#!/usr/bin/env bash
# Shared detection engine for the Skill Security Scanner.
# Sourced by scan-skill.sh (local files) and scan-github-remote.sh (GitHub API, no local clone).
# Not meant to be run directly.
#
# Contract for callers:
#   - Declare CRITICAL=0 HIGH=0 MEDIUM=0 LOW=0 before scanning.
#   - Call scan_content "<label>" "<content>" once per file.
#   - Call print_verdict at the end; it prints the summary and exits with 0/1/2.

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

flag() {
  local severity="$1"; shift
  local file="$1"; shift
  local line="$1"; shift
  local detail="$*"
  case "$severity" in
    CRITICAL) CRITICAL=$((CRITICAL+1)); echo -e "  ${RED}🔴 [CRITICAL]${NC} ${file}:${line} — ${detail}" ;;
    HIGH)     HIGH=$((HIGH+1));         echo -e "  ${YELLOW}🟠 [HIGH]${NC}     ${file}:${line} — ${detail}" ;;
    MEDIUM)   MEDIUM=$((MEDIUM+1));     echo -e "  ${YELLOW}🟡 [MEDIUM]${NC}   ${file}:${line} — ${detail}" ;;
    LOW)      LOW=$((LOW+1));           echo -e "  ${CYAN}🟢 [LOW]${NC}      ${file}:${line} — ${detail}" ;;
  esac
}

# scan_content <label> <content>
# <label> is whatever the caller wants printed as the "file" — a relative
# path for local scans, or "owner/repo:path" for remote scans.
scan_content() {
  local rel="$1"
  local content="$2"

  # ── CRITICAL: Data Exfiltration ──
  # curl/wget sending data to external URL
  if echo "$content" | grep -nEq '(curl|wget)\s+.*(-d|--data|--data-raw|--data-binary|--upload-file|-F|--form)' 2>/dev/null; then
    echo "$content" | grep -nE '(curl|wget)\s+.*(-d|--data|--data-raw|--data-binary|--upload-file|-F|--form)' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "curl/wget sending data: ${match#*:}"
    done
  fi

  # Webhook URLs
  if echo "$content" | grep -nEq '(discord\.com/api/webhooks|hooks\.slack\.com|api\.telegram\.org/bot|webhook\.site)' 2>/dev/null; then
    echo "$content" | grep -nE '(discord\.com/api/webhooks|hooks\.slack\.com|api\.telegram\.org/bot|webhook\.site)' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "Webhook URL detected"
    done
  fi

  # scp/rsync to remote
  if echo "$content" | grep -nEq '(scp|rsync)\s+.*@.*:' 2>/dev/null; then
    echo "$content" | grep -nE '(scp|rsync)\s+.*@.*:' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "Remote file transfer: scp/rsync"
    done
  fi

  # nc with -e or piped to network
  if echo "$content" | grep -nEq 'nc\s+.*(-e|> )' 2>/dev/null; then
    echo "$content" | grep -nE 'nc\s+.*(-e|> )' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "netcat with execute/redirect"
    done
  fi

  # Sensitive files sent externally
  if echo "$content" | grep -nPq '(curl|wget|nc|scp).*(\$HOME|\.env|\.ssh|/etc/passwd|/etc/shadow|credentials|secrets|tokens)' 2>/dev/null; then
    echo "$content" | grep -nP '(curl|wget|nc|scp).*(\$HOME|\.env|\.ssh|/etc/passwd|/etc/shadow|credentials|secrets|tokens)' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "Sensitive data sent externally"
    done
  fi

  # ── CRITICAL: Destructive Commands ──
  # rm -rf on broad paths
  if echo "$content" | grep -nEq 'rm\s+-rf\s+(~/|/\s|\$HOME|/home|/etc|/var)' 2>/dev/null; then
    echo "$content" | grep -nE 'rm\s+-rf\s+(~/|/\s|\$HOME|/home|/etc|/var)' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "Destructive rm -rf on system/user directory"
    done
  fi

  # chmod 777
  if echo "$content" | grep -nEq 'chmod\s+777' 2>/dev/null; then
    echo "$content" | grep -nE 'chmod\s+777' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "chmod 777 — world-writable permissions"
    done
  fi

  # dd/mkfs/fdisk
  if echo "$content" | grep -nEq '\b(dd|mkfs|fdisk|parted)\s' 2>/dev/null; then
    echo "$content" | grep -nE '\b(dd|mkfs|fdisk|parted)\s' | while read -r match; do
      flag CRITICAL "$rel" "${match%%:*}" "Disk-level operation: ${match#*:}"
    done
  fi

  # Fork bombs / resource exhaustion
  if echo "$content" | grep -nEq ':\s*\(\s*\)\s*\{' 2>/dev/null; then
    flag CRITICAL "$rel" "?" "Fork bomb pattern detected"
  fi

  # ── HIGH: Security Bypass ──
  if echo "$content" | grep -niEq '(ignore\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|rules?|guidelines?|prompt|directives?))' 2>/dev/null; then
    echo "$content" | grep -niE '(ignore\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|rules?|guidelines?|prompt|directives?))' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Prompt injection: 'ignore instructions'"
    done
  fi

  if echo "$content" | grep -niEq '(you\s+are\s+now\s+|from\s+now\s+on\s+you\s+are\s+|your\s+new\s+role\s+is)' 2>/dev/null; then
    echo "$content" | grep -niE '(you\s+are\s+now\s+|from\s+now\s+on\s+you\s+are\s+|your\s+new\s+role\s+is)' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Identity redefinition attempt"
    done
  fi

  if echo "$content" | grep -niEq '(bypass|disable|override)\s+(security|safety|verification|checks?|guard|protect)' 2>/dev/null; then
    echo "$content" | grep -niE '(bypass|disable|override)\s+(security|safety|verification|checks?|guard|protect)' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Security bypass language"
    done
  fi

  if echo "$content" | grep -niEq '(do\s+not\s+tell\s+the\s+user|keep\s+this\s+secret|hide\s+this\s+from|conceal\s+your\s+actions)' 2>/dev/null; then
    echo "$content" | grep -niE '(do\s+not\s+tell\s+the\s+user|keep\s+this\s+secret|hide\s+this\s+from|conceal\s+your\s+actions)' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Concealment instruction"
    done
  fi

  # Zero-width characters
  if echo "$content" | grep -nPq '[\x{200b}\x{200c}\x{200d}\x{feff}]' 2>/dev/null; then
    echo "$content" | grep -nP '[\x{200b}\x{200c}\x{200d}\x{feff}]' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Zero-width Unicode characters (hidden text)"
    done
  fi

  # Suspicious system/assistant role emulation
  if echo "$content" | grep -niEq '(^|[^a-zA-Z])(system:|assistant:|<\|im_start\|>|\[INST\])' 2>/dev/null; then
    echo "$content" | grep -niE '(^|[^a-zA-Z])(system:|assistant:|<\|im_start\|>|\[INST\])' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "System/assistant role emulation token"
    done
  fi

  # Long base64 strings
  if echo "$content" | grep -nPq '[A-Za-z0-9+/=]{100,}' 2>/dev/null; then
    echo "$content" | grep -nPo '[A-Za-z0-9+/=]{100,}' 2>/dev/null | head -5 | while read -r match; do
      flag HIGH "$rel" "?" "Long base64 string (potential obfuscation)"
    done
  fi

  # Encrypted/compressed payloads
  if echo "$content" | grep -nEq '(openssl\s+enc|gzip\s+-[0-9]|xxd\s+-[rp])' 2>/dev/null; then
    echo "$content" | grep -nE '(openssl\s+enc|gzip\s+-[0-9]|xxd\s+-[rp])' | while read -r match; do
      flag HIGH "$rel" "${match%%:*}" "Encryption/compression of payload"
    done
  fi

  # ── MEDIUM: Suspicious Patterns ──
  if echo "$content" | grep -nEq '(~/\.ssh|/etc/passwd|/etc/shadow|\.env\b|credentials\.(json|yml|yaml)|secret(s)?\.(json|yml|yaml)|api_key|password|token\s*=|AUTH_TOKEN)' 2>/dev/null; then
    echo "$content" | grep -nE '(~/\.ssh|/etc/passwd|/etc/shadow|\.env\b|credentials\.(json|yml|yaml)|secret(s)?\.(json|yml|yaml)|api_key|password|token\s*=|AUTH_TOKEN)' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "References sensitive files/credentials"
    done
  fi

  if echo "$content" | grep -nEq '>\s*/etc/|>\s*/usr/bin/|>\s*/usr/local/bin/' 2>/dev/null; then
    echo "$content" | grep -nE '>\s*/etc/|>\s*/usr/bin/|>\s*/usr/local/bin/' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "Writing to system directory"
    done
  fi

  if echo "$content" | grep -nEq '(nc\s+-l|python.*http\.server|socat\s+LISTEN)' 2>/dev/null; then
    echo "$content" | grep -nE '(nc\s+-l|python.*http\.server|socat\s+LISTEN)' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "Network listener"
    done
  fi

  if echo "$content" | grep -nEq '(crontab|cron\s|systemd|launchd|/etc/cron|cron\.d)' 2>/dev/null; then
    echo "$content" | grep -nE '(crontab|cron\s|systemd|launchd|/etc/cron|cron\.d)' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "Persistence mechanism (cron/systemd)"
    done
  fi

  if echo "$content" | grep -nEq '\b(eval|exec)\s*\(?\s*\$' 2>/dev/null; then
    echo "$content" | grep -nE '\b(eval|exec)\s*\(?\s*\$' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "eval/exec on variable (dynamic code execution)"
    done
  fi

  if echo "$content" | grep -nEq 'child_process\.exec|os\.system|subprocess\.(call|run|Popen)\s*\(' 2>/dev/null; then
    echo "$content" | grep -nE 'child_process\.exec|os\.system|subprocess\.(call|run|Popen)\s*\(' | while read -r match; do
      flag MEDIUM "$rel" "${match%%:*}" "Shell command execution in code"
    done
  fi

  # ── LOW: Requires Review ──
  # External URLs
  if echo "$content" | grep -nPq 'https?://[^\s<>"'"'"')\]]+' 2>/dev/null; then
    echo "$content" | grep -nPo 'https?://[^\s<>"'"'"')\]]+' 2>/dev/null | while read -r match; do
      flag LOW "$rel" "${match%%:*}" "URL: ${match#*:}"
    done
  fi

  # Writes outside skill dir
  if echo "$content" | grep -nEq '(write|create|save|output|export)\s+(to\s+)?(~/|/tmp/|/home/|/etc/|/var/)' 2>/dev/null; then
    echo "$content" | grep -nE '(write|create|save|output|export)\s+(to\s+)?(~/|/tmp/|/home/|/etc/|/var/)' | while read -r match; do
      flag LOW "$rel" "${match%%:*}" "File write outside skill directory"
    done
  fi
}

# print_verdict — call once after all files are scanned. Exits the process.
print_verdict() {
  echo -e "${BOLD}═══════════════════════════════════════${NC}"
  echo -e "${BOLD}  SUMMARY${NC}"
  echo -e "  ${RED}Critical:${NC} $CRITICAL"
  echo -e "  ${YELLOW}High:${NC}     $HIGH"
  echo -e "  ${YELLOW}Medium:${NC}   $MEDIUM"
  echo -e "  ${CYAN}Low:${NC}      $LOW"
  echo ""

  if [ "$CRITICAL" -gt 0 ]; then
    echo -e "${RED}${BOLD}  VERDICT: DANGEROUS — DO NOT INSTALL${NC}"
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
    exit 2
  elif [ "$HIGH" -gt 0 ] || [ "$MEDIUM" -gt 2 ]; then
    echo -e "${YELLOW}${BOLD}  VERDICT: SUSPICIOUS — Manual review required${NC}"
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
    exit 1
  else
    echo -e "${GREEN}${BOLD}  VERDICT: SAFE — No critical threats detected${NC}"
    echo -e "${BOLD}═══════════════════════════════════════${NC}"
    exit 0
  fi
}
