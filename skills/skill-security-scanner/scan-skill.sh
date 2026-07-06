#!/usr/bin/env bash
# Skill Security Scanner — Automated first-pass scan (local files)
# Usage: ./scan-skill.sh <path-to-skill-directory-or-file>
# Exit codes: 0=SAFE, 1=SUSPICIOUS, 2=DANGEROUS

set -euo pipefail
shopt -s lastpipe  # keep `... | while read` loops in the current shell so flag() counters persist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=skill-scan-lib.sh
source "$SCRIPT_DIR/skill-scan-lib.sh"

show_help() {
  cat <<EOF
${BOLD}Skill Security Scanner — local scan${NC}

Scans a skill (SKILL.md + companion scripts) on your local disk for
malicious content before you install or trust it: data exfiltration,
destructive commands, prompt injection, obfuscation, suspicious patterns.

${BOLD}Usage:${NC}
  $0 <path-to-skill-directory-or-file>
  $0 -h | --help

${BOLD}Examples:${NC}
  $0 ~/skills/some-skill/            # scan a whole skill folder
  $0 ~/skills/some-skill/SKILL.md    # scan a single file

${BOLD}Exit codes:${NC}
  0  SAFE        no critical/high findings, at most 2 medium
  1  SUSPICIOUS  at least 1 high finding, or 3+ medium findings
  2  DANGEROUS   at least 1 critical finding — do not install

${BOLD}See also:${NC}
  scan-github-skill.sh    scan a GitHub repo via a temporary local clone
  scan-github-remote.sh   scan a GitHub repo with no clone / no disk writes
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  if [ -t 0 ]; then
    echo -e "${BOLD}Skill Security Scanner${NC} — no path given."
    read -r -p "Enter the path to a skill directory or file to scan (or --help for usage): " TARGET
    echo ""
    case "$TARGET" in
      -h|--help) show_help; exit 0 ;;
    esac
  fi
  if [ -z "$TARGET" ]; then
    echo -e "${RED}Usage: $0 <path-to-skill-directory-or-file>${NC}  (run '$0 --help' for details)"
    exit 2
  fi
fi

if [ ! -e "$TARGET" ]; then
  echo -e "${RED}Error: '$TARGET' does not exist${NC}"
  exit 2
fi

CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# Resolve to directory
if [ -f "$TARGET" ]; then
  SKILL_DIR="$(dirname "$TARGET")"
  FILES=("$TARGET")
else
  SKILL_DIR="$TARGET"
  FILES=()
  while IFS= read -r -d '' f; do
    FILES+=("$f")
  done < <(find "$SKILL_DIR" -type f \( -name "*.md" -o -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.json" -o -name "*.txt" -o -name "*.yaml" -o -name "*.yml" -o -name "*.toml" \) -print0 2>/dev/null || true)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo -e "${YELLOW}No scannable files found in $SKILL_DIR${NC}"
  exit 1
fi

# ── Header ────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD}  SKILL SECURITY SCAN${NC}"
echo -e "${BOLD}  Target:${NC} $TARGET"
echo -e "${BOLD}  Files:${NC}  ${#FILES[@]}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo ""

# ── Scan all files ──
for f in "${FILES[@]}"; do
  rel="${f#$SKILL_DIR/}"
  echo -e "${BOLD}── Scanning:${NC} $rel"
  content="$(cat "$f" 2>/dev/null)" || { echo ""; continue; }
  scan_content "$rel" "$content"
  echo ""
done

print_verdict
