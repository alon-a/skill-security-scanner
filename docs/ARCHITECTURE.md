Here's how the whole thing fits together, in order of execution.

## The pieces

1. **[SKILL.md](../skills/skill-security-scanner/SKILL.md)** — not code, it's *instructions for an AI* (Claude Code reads this when the skill is invoked). It defines what to look for and how to phrase the verdict.
2. **[skill-scan-lib.sh](../skills/skill-security-scanner/skill-scan-lib.sh)** — the shared detection engine. Defines `flag()`, `scan_content()` (the ~20 regex checks), and `print_verdict()`. Not run directly — it's `source`d by the two scanners below, so the checks live in exactly one place.
3. **[scan-skill.sh](../skills/skill-security-scanner/scan-skill.sh)** — CLI entry point for a **local** file or directory. Resolves the target, reads each file from disk, and calls into the shared lib.
4. **[scan-github-skill.sh](../skills/skill-security-scanner/scan-github-skill.sh)** — CLI entry point for a remote GitHub repo via a **temporary local clone** (git-based).
5. **[scan-github-remote.sh](../skills/skill-security-scanner/scan-github-remote.sh)** — CLI entry point for a remote GitHub repo via the **GitHub API, with no local clone at all** — every file is fetched straight into memory, scanned, and discarded.

There are two ways to trigger a scan — via the AI reading SKILL.md, or by running one of the three scripts directly — and all of them converge on the same severity model, because they all call the same `scan_content()`/`print_verdict()` from `skill-scan-lib.sh`.

## Step by step: `skill-scan-lib.sh` (the shared detection engine)

1. **Colors + `flag()`**: given a severity (`CRITICAL/HIGH/MEDIUM/LOW`), a label, a line number, and a description, `flag()` increments the matching counter and prints a colored line. This is the single place that turns "a regex matched" into "a counted finding."

2. **`scan_content(label, content)`**: the actual detection logic, called once per file by whichever entry-point script found it. Runs ~20 independent checks, each following the same two-step pattern:
   ```
   if echo "$content" | grep -q 'PATTERN'; then      # does it match at all?
     echo "$content" | grep 'PATTERN' | while read match; do   # get every matching line
       flag SEVERITY "$label" "$line" "description"
     done
   fi
   ```
   The checks are grouped by severity, matching the table in SKILL.md:
   - **CRITICAL** — exfiltration (`curl -d` to an external host, webhook URLs, `scp`/`rsync`, netcat reverse shells, secrets being piped out), and destructive commands (`rm -rf` on broad paths, `chmod 777`, disk tools, fork bombs).
   - **HIGH** — prompt-injection phrasing ("ignore previous instructions," "you are now," "keep this secret"), fake system/assistant tokens, zero-width Unicode, long base64 blobs, encrypted payloads.
   - **MEDIUM** — references to sensitive files (`.env`, `~/.ssh`), writes to system dirs, network listeners, cron/persistence, dynamic `eval`/`exec`.
   - **LOW** — just informational: every external URL found, and writes outside the skill's own directory.

   `set -euo pipefail` + `shopt -s lastpipe` (set by whichever entry-point script sourced this file) keeps the `| while read` loops running in the current shell, not a subshell — otherwise the counters silently never update.

3. **`print_verdict()`**: called once, after every file has been scanned. Checks the four running totals:
   - Any `CRITICAL` > 0 → **DANGEROUS**, exit code `2`.
   - Else any `HIGH` > 0, or `MEDIUM` > 2 → **SUSPICIOUS**, exit code `1`.
   - Otherwise → **SAFE**, exit code `0`.

   This exit code is the machine-readable part — anything scripting around these tools can branch on it.

## Step by step: `scan-skill.sh` (local files)

1. Sources `skill-scan-lib.sh` from its own directory.
2. Resolves the target — a single file, or a directory walked with `find` for every `.md .sh .py .js .ts .json .txt .yaml .yml .toml` file.
3. If nothing matches, exits early as `SUSPICIOUS` (exit 1) — an empty skill folder isn't "safe," it's unscannable.
4. For each file: reads it with `cat`, calls `scan_content "<relative path>" "$content"`.
5. Calls `print_verdict` at the end.

## Step by step: `scan-github-skill.sh` (remote via temporary clone)

1. Takes a GitHub URL (optionally a `/tree/branch/subpath` URL for monorepos) and parses out the clone URL, branch, and subpath with `sed`.
2. `mktemp -d` creates a scratch directory, and `trap "rm -rf ... " EXIT` guarantees it's deleted no matter how the script exits (success, error, or Ctrl-C).
3. Shallow-clones the repo (`--depth 1 --single-branch`) into that temp dir — fast, and doesn't pull the whole git history.
4. If a subpath was given (monorepo case), narrows `SCAN_TARGET` to that subfolder; falls back to the whole repo if the subpath doesn't exist.
5. Prints repo metadata (owner, name, branch, file count) purely for the human reading the output.
6. Calls `scan-skill.sh` on `SCAN_TARGET` — **every repo goes through this unconditionally**, no shortcut based on repo/org name (a previous "trusted if URL contains 'anthropics'" idea was removed entirely, since that string is trivially spoofable).
7. On exit (any path), the `trap` fires and wipes the temp clone. Note the repo content does sit on disk, briefly, during the scan itself.

## Step by step: `scan-github-remote.sh` (remote, no clone, no disk writes)

This is the answer to "can we verify a GitHub repo without downloading it": yes, by talking to the GitHub API/CDN directly instead of `git clone`.

1. Sources `skill-scan-lib.sh`, same as the local scanner.
2. **Dependency check**: requires `curl`, and a working Python 3 (`python3` or `python` — whichever actually runs, since e.g. Windows' `python3` PATH stub without a real install doesn't count). Python's `json` module is used to parse GitHub API responses correctly, instead of regex-on-JSON.
3. Parses the URL the same way as `scan-github-skill.sh` (owner/repo/branch/subpath).
4. If no branch was given, calls `GET /repos/{owner}/{repo}` and reads `.default_branch` from the JSON.
5. **The key step**: calls `GET /repos/{owner}/{repo}/git/trees/{branch}?recursive=1` — one API call returns the entire file tree (paths, types, sizes) without transferring any file content. A Python snippet filters this down to blobs matching the scannable extensions, honoring the subpath filter, skipping anything over 2MB, and warning if GitHub truncated the listing (repo too large for one response).
6. For each matching path: builds a `raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}` URL (percent-encoded via Python) and fetches it with `curl` straight into a shell variable — never `-o` to a file. That variable is what `scan_content()` sees; once the loop moves to the next file, that content is gone.
7. Calls `print_verdict` at the end, same exit codes as the other two scanners.
8. Optional `GITHUB_TOKEN` env var — added as an `Authorization: Bearer` header on API calls — raises the rate limit from 60/hr to 5000/hr and allows scanning private repos the token can access.

Trade-off vs. the clone-based scanner: never touches disk, but relies on the GitHub API (rate limits, and a truncated tree on very large repos), whereas `git clone` sees the whole repo regardless of size.

## How SKILL.md fits in

When you ask Claude Code to "scan the skill at X," it doesn't run the script blindly — it reads SKILL.md as its own instructions and does a *second*, more contextual pass: reading the SKILL.md prose itself for contradictory instructions, checking whether the skill asks for more file access than it needs, and applying the "Red Flags" section (unexplained scripts, URL shorteners, no reputation signals) — things a regex can't catch, like a cleverly-worded social-engineering paragraph. The automated script is the fast first pass; the AI reading SKILL.md is meant to be the deeper second pass. The doc is explicit about this limitation: *"זה כלי עזר, לא חומת מגן"* — "this is a helper tool, not a firewall."