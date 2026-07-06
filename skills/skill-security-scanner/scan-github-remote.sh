#!/usr/bin/env bash
# GitHub Skill Scanner — remote verification via the GitHub API, no local clone.
# Every file is fetched into memory, scanned, and discarded — nothing touches disk.
#
# Usage: ./scan-github-remote.sh <github-url> [branch]
# Examples:
#   ./scan-github-remote.sh https://github.com/some-user/some-skill
#   ./scan-github-remote.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
#
# Auth (optional, recommended): export GITHUB_TOKEN=<personal access token>
#   Raises the API rate limit from 60/hr to 5000/hr and allows scanning
#   private repos the token can read.
#
# Exit codes: 0=SAFE, 1=SUSPICIOUS, 2=DANGEROUS

set -euo pipefail
shopt -s lastpipe

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=skill-scan-lib.sh
source "$SCRIPT_DIR/skill-scan-lib.sh"

MAX_FILE_SIZE=2000000  # bytes; skip anything bigger instead of pulling huge blobs into memory

show_help() {
  cat <<EOF
${BOLD}GitHub Skill Scanner — remote verification, no clone, no disk writes${NC}

Scans a GitHub repo without ever running 'git clone'. Lists the file
tree via the GitHub API (one call), then fetches each scannable file's
content straight into memory over raw.githubusercontent.com and scans
it there. Nothing from the repo is ever written to disk.

${BOLD}Usage:${NC}
  $0 <github-url> [branch]
  $0 -h | --help

${BOLD}Examples:${NC}
  $0 https://github.com/user/skill-repo
  $0 https://github.com/user/skill-repo/tree/main/skills/my-skill

${BOLD}Requires:${NC} curl, and a working python3 (or python) for JSON parsing.

${BOLD}Optional:${NC} export GITHUB_TOKEN=<personal access token>
  Raises the API rate limit from 60/hr to 5000/hr and allows scanning
  private repos the token can read.

${BOLD}Limitation:${NC} if GitHub truncates the tree listing (very large repos),
this scanner warns and may miss files — use scan-github-skill.sh (clone-based)
for guaranteed full coverage in that case.

${BOLD}Exit codes:${NC}
  0  SAFE        1  SUSPICIOUS        2  DANGEROUS

${BOLD}See also:${NC}
  scan-skill.sh           scan a local file or directory
  scan-github-skill.sh    scan a GitHub repo via a temporary local clone
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

URL="${1:-}"
BRANCH_ARG="${2:-}"

if [ -z "$URL" ]; then
  if [ -t 0 ]; then
    echo -e "${BOLD}GitHub Skill Scanner (remote, no clone)${NC} — no URL given."
    read -r -p "Enter the GitHub repo URL to scan (or --help for usage): " URL
    echo ""
    case "$URL" in
      -h|--help) show_help; exit 0 ;;
    esac
  fi
  if [ -z "$URL" ]; then
    echo -e "${RED}Usage: $0 <github-url> [branch]${NC}  (run '$0 --help' for details)"
    echo "Example: $0 https://github.com/user/skill-repo"
    echo "Example: $0 https://github.com/user/skill-repo/tree/main/skills/my-skill"
    exit 2
  fi
fi

# ── Dependencies ──
if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Error: curl is required.${NC}"
  exit 2
fi

PYTHON=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import json" >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo -e "${RED}Error: a working Python 3 interpreter (python3 or python) is required to parse GitHub API responses.${NC}"
  exit 2
fi

# ── Auth ──
CURL_AUTH_ARGS=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  CURL_AUTH_ARGS=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

api_get() {
  curl -sS -H "Accept: application/vnd.github+json" "${CURL_AUTH_ARGS[@]}" "$1"
}

# ── Parse URL: owner, repo, branch, subpath ──
# Handles: github.com/owner/repo, github.com/owner/repo/tree/branch/sub/path
if echo "$URL" | grep -q '/tree/'; then
  REPO_ROOT=$(echo "$URL" | sed -E 's|(https?://github\.com/[^/]+/[^/]+).*|\1|')
  BRANCH=$(echo "$URL" | sed -E 's|.*/tree/([^/]+).*|\1|')
  SUBPATH=$(echo "$URL" | sed -E 's|.*/tree/[^/]+/(.*)|\1|')
else
  REPO_ROOT=$(echo "$URL" | sed -E 's|(https?://github\.com/[^/]+/[^/]+).*|\1|')
  BRANCH=""
  SUBPATH=""
fi
OWNER=$(echo "$REPO_ROOT" | sed -E 's|.*github\.com/([^/]+)/.*|\1|')
REPO=$(echo "$REPO_ROOT" | sed -E 's|.*github\.com/[^/]+/([^/]+).*|\1|' | sed -E 's|\.git$||')

if [ -n "$BRANCH_ARG" ]; then
  BRANCH="$BRANCH_ARG"
fi

echo ""
echo -e "${BOLD}🔍 Resolving $OWNER/$REPO...${NC}"

if [ -z "$BRANCH" ]; then
  REPO_INFO_JSON="$(api_get "https://api.github.com/repos/$OWNER/$REPO")"
  BRANCH="$(printf '%s' "$REPO_INFO_JSON" | "$PYTHON" -c '
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, dict) or "default_branch" not in data:
    sys.stderr.write("error: " + data.get("message", "unexpected response") + "\n")
    sys.exit(1)
print(data["default_branch"])
')" || { echo -e "${RED}Error: could not resolve $OWNER/$REPO (repo may not exist, or is private — set GITHUB_TOKEN).${NC}"; exit 2; }
fi

echo -e "${BOLD}📊 Repo:${NC} $OWNER/$REPO"
echo -e "${BOLD}   Branch:${NC} $BRANCH"
[ -n "$SUBPATH" ] && echo -e "${BOLD}   Subpath:${NC} $SUBPATH"
echo ""

# ── List the file tree via the API (one call, no clone) ──
TREE_JSON="$(api_get "https://api.github.com/repos/$OWNER/$REPO/git/trees/$BRANCH?recursive=1")"

FILTER_PY='
import json, os, sys

data = json.load(sys.stdin)
if not isinstance(data, dict) or "tree" not in data:
    sys.stderr.write("error: " + str(data.get("message", "unexpected response")) + "\n")
    sys.exit(1)

if data.get("truncated"):
    sys.stderr.write("WARNING: GitHub truncated this tree listing (repo too large) — some files were not seen.\n")

exts = {".md", ".sh", ".py", ".js", ".ts", ".json", ".txt", ".yaml", ".yml", ".toml"}
subpath = sys.argv[1] if len(sys.argv) > 1 else ""
max_size = int(sys.argv[2]) if len(sys.argv) > 2 else 2_000_000

for entry in data["tree"]:
    if entry.get("type") != "blob":
        continue
    path = entry["path"]
    if subpath and not (path == subpath or path.startswith(subpath.rstrip("/") + "/")):
        continue
    _, ext = os.path.splitext(path)
    if ext.lower() not in exts:
        continue
    size = entry.get("size", 0)
    if size > max_size:
        sys.stderr.write(f"skipping {path} ({size} bytes > {max_size} limit)\n")
        continue
    sys.stdout.write(path + "\0")
'

FILES=()
while IFS= read -r -d '' p; do
  FILES+=("$p")
done < <(printf '%s' "$TREE_JSON" | "$PYTHON" -c "$FILTER_PY" "$SUBPATH" "$MAX_FILE_SIZE") \
  || { echo -e "${RED}Error listing repo tree for $OWNER/$REPO@$BRANCH.${NC}"; exit 2; }

if [ ${#FILES[@]} -eq 0 ]; then
  echo -e "${YELLOW}No scannable files found in $OWNER/$REPO${SUBPATH:+/$SUBPATH}${NC}"
  exit 1
fi

echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo -e "${BOLD}  SKILL SECURITY SCAN (remote, no clone)${NC}"
echo -e "${BOLD}  Target:${NC} $OWNER/$REPO@$BRANCH${SUBPATH:+/$SUBPATH}"
echo -e "${BOLD}  Files:${NC}  ${#FILES[@]}"
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo ""

encode_path() {
  "$PYTHON" -c 'import sys, urllib.parse; print("/".join(urllib.parse.quote(seg) for seg in sys.argv[1].split("/")))' "$1"
}

CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# ── Fetch each file's content straight into memory and scan it ──
for path in "${FILES[@]}"; do
  enc_path="$(encode_path "$path")"
  raw_url="https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/$enc_path"

  echo -e "${BOLD}── Scanning:${NC} $path"

  content=""
  if ! content="$(curl -sS -f "${CURL_AUTH_ARGS[@]}" "$raw_url")"; then
    echo -e "  ${YELLOW}(skip) failed to fetch $path${NC}"
    echo ""
    continue
  fi

  scan_content "$path" "$content"
  echo ""
done

print_verdict
