#!/usr/bin/env bash
# GitHub Skill Scanner — clone + scan + cleanup
# Usage: ./scan-github-skill.sh <github-url> [branch]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/scan-skill.sh"

show_help() {
  cat <<EOF
GitHub Skill Scanner — scan via a temporary local clone

Shallow-clones a GitHub repo into a temp directory, runs the same checks
as scan-skill.sh against it, then deletes the clone automatically (even
on error or Ctrl-C). Repo content briefly touches disk during the scan.
Use this over scan-github-remote.sh for very large repos, where the
GitHub API's file-listing can get truncated.

Usage:
  $0 <github-url> [branch]
  $0 -h | --help

Examples:
  $0 https://github.com/user/skill-repo
  $0 https://github.com/user/skill-repo/tree/main/skills/my-skill

Exit codes:
  0  SAFE        1  SUSPICIOUS        2  DANGEROUS

See also:
  scan-skill.sh           scan a local file or directory
  scan-github-remote.sh   scan a GitHub repo with no clone / no disk writes
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

URL="${1:-}"
BRANCH="${2:-main}"

if [ -z "$URL" ]; then
  if [ -t 0 ]; then
    echo "GitHub Skill Scanner — no URL given."
    read -r -p "Enter the GitHub repo URL to scan (or --help for usage): " URL
    echo ""
    case "$URL" in
      -h|--help) show_help; exit 0 ;;
    esac
  fi
  if [ -z "$URL" ]; then
    echo "Usage: $0 <github-url> [branch]  (run '$0 --help' for details)"
    echo "Example: $0 https://github.com/user/skill-repo"
    echo "Example: $0 https://github.com/user/skill-repo/tree/main/skills/my-skill"
    exit 2
  fi
fi

# Convert web URL to clone URL if needed
# Handles: github.com/user/repo, github.com/user/repo/tree/branch/path
if echo "$URL" | grep -q '/tree/'; then
  # Extract repo root and subpath
  REPO_ROOT=$(echo "$URL" | sed -E 's|(https?://github\.com/[^/]+/[^/]+).*|\1|')
  BRANCH=$(echo "$URL" | sed -E 's|.*/tree/([^/]+).*|\1|')
  SUBPATH=$(echo "$URL" | sed -E 's|.*/tree/[^/]+/(.*)|\1|')
  CLONE_URL="${REPO_ROOT}.git"
else
  CLONE_URL=$(echo "$URL" | sed -E 's|(https?://github\.com/[^/]+/[^/]+).*|\1.git|')
  SUBPATH=""
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

echo ""
echo "🔽 Cloning $CLONE_URL (branch: $BRANCH)..."
git clone --depth 1 --single-branch --branch "$BRANCH" "$CLONE_URL" "$TEMP_DIR" 2>&1 | tail -1

SCAN_TARGET="$TEMP_DIR"
if [ -n "$SUBPATH" ]; then
  SCAN_TARGET="$TEMP_DIR/$SUBPATH"
  if [ ! -d "$SCAN_TARGET" ]; then
    echo "⚠️  Sub-path '$SUBPATH' not found, scanning entire repo"
    SCAN_TARGET="$TEMP_DIR"
  fi
fi

echo ""

# ── Quick GitHub metadata ──
REPO_NAME=$(echo "$CLONE_URL" | sed -E 's|.*/(.+)\.git|\1|')
REPO_OWNER=$(echo "$CLONE_URL" | sed -E 's|.*github\.com/([^/]+).*|\1|')

echo "📊 Repo: $REPO_OWNER/$REPO_NAME"
echo "   Branch: $BRANCH"
echo "   Files in target: $(find "$SCAN_TARGET" -type f | wc -l)"
echo ""

# Every source is scanned the same way — no shortcuts based on repo/org name,
# since that string is trivially spoofable (e.g. "anthropics-fork").

# ── Run the scanner ──
"$SCANNER" "$SCAN_TARGET"