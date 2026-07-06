# skill-security-scanner

Scan a Claude Code skill — `SKILL.md` plus its companion scripts — for
malicious content **before** you install it, update it from an external
source, or trust a skill you're about to share. Checks for data
exfiltration, destructive commands, prompt injection, obfuscation, and
other suspicious patterns.

Works on a local folder, or on a remote GitHub repo — either via a
temporary local clone, or with **zero disk writes at all** (every file is
fetched straight into memory over the GitHub API and discarded after
scanning).

> This is a helper, not a firewall. A sufficiently clever skill can dodge
> regex checks. Always pair this with a manual read of the `SKILL.md`
> prose, a look at who published it, and — for anything you don't fully
> trust — a first run in a sandbox. See [Limitations](#limitations) below.

> **Curious and scanning this repo on itself?** You'll get a `DANGEROUS`
> verdict — that's expected. `SKILL.md` documents the exact patterns this
> tool detects (e.g. `curl -d ... /etc/passwd` as a worked example of what
> exfiltration looks like), so the scanner correctly matches its own
> documentation. It's not a live payload.

## What it checks

| Severity | Examples |
|---|---|
| 🔴 **CRITICAL** | `curl`/`wget` exfiltrating data, webhook URLs (Discord/Slack/Telegram), `scp`/`rsync`/netcat to unknown hosts, `rm -rf` on broad paths, `chmod 777`, disk-level commands (`dd`/`mkfs`/`fdisk`), fork bombs |
| 🟠 **HIGH** | Prompt-injection phrasing ("ignore previous instructions", "you are now…"), fake `system:`/`assistant:`/`[INST]` tokens, zero-width Unicode, long unexplained base64 blobs, encrypted/compressed payloads |
| 🟡 **MEDIUM** | References to `.env`/`~/.ssh`/credentials, writes to system directories, network listeners, cron/systemd persistence, dynamic `eval`/`exec` |
| 🟢 **LOW** | Every external URL found, file writes outside the skill's own directory |

Full detection table: [skills/skill-security-scanner/SKILL.md](skills/skill-security-scanner/SKILL.md).

**Verdict & exit codes** — printed after every scan, and usable in scripts/CI:

| Verdict | Condition | Exit code |
|---|---|---|
| SAFE | 0 critical, 0 high, ≤2 medium | `0` |
| SUSPICIOUS | 0 critical, but ≥1 high or ≥3 medium | `1` |
| DANGEROUS | ≥1 critical | `2` |

## Install

### Option A — Claude Code plugin (marketplace)

This repo is itself a valid plugin marketplace (`.claude-plugin/marketplace.json`
+ `.claude-plugin/plugin.json`). From Claude Code:

```
/plugin marketplace add alon-a/skill-security-scanner
/plugin install skill-security-scanner
```

(Claude Code's plugin command syntax may vary by version — run `/plugin`
or `/help` if the above doesn't match what you see.)

### Option B — Manual skill install (no plugin system needed)

Copy the skill folder into Claude Code's skills directory:

```bash
# personal (all projects):
cp -r skills/skill-security-scanner ~/.claude/skills/

# or project-local (this repo only):
cp -r skills/skill-security-scanner /path/to/your-project/.claude/skills/
```

Then just ask Claude Code in that project: *"scan the skill at
\<path-or-URL\> for security issues"* — it reads `SKILL.md` for the full
checklist and runs the matching script underneath.

### Option C — Standalone CLI (no AI tool required)

The scripts are plain bash — they work with or without Claude Code:

```bash
git clone https://github.com/alon-a/skill-security-scanner
cd skill-security-scanner/skills/skill-security-scanner
chmod +x *.sh
./scan-skill.sh --help
```

### Option D — Cursor

Cursor doesn't have a plugin-installer equivalent to Claude Code's, but
this repo includes `.cursor/rules/skill-security-scanner.mdc`, which tells
Cursor's agent that these scripts exist and how to invoke them. Clone the
repo (or copy `skills/skill-security-scanner/` into your project), and
either let the Cursor agent run the scripts for you, or run them yourself
from Cursor's integrated terminal (Git Bash/WSL — not PowerShell, see
[Requirements](#requirements)).

## Usage

Three entry points, sharing one detection engine (`skill-scan-lib.sh`):

**1. Local file or folder**
```bash
./scan-skill.sh ~/skills/some-skill/
./scan-skill.sh ~/skills/some-skill/SKILL.md
```

**2. Remote GitHub repo, via a temporary clone (git-based)**
```bash
./scan-github-skill.sh https://github.com/some-user/some-skill

# monorepo, specific branch/subfolder:
./scan-github-skill.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```
Shallow-clones into a temp dir, scans, deletes the clone on exit (even on
error or Ctrl-C via `trap`). Repo content briefly touches disk during the
scan. Use this for very large repos, where the API-based tree listing
can get truncated.

**3. Remote GitHub repo, no clone, no disk writes**
```bash
./scan-github-remote.sh https://github.com/some-user/some-skill
./scan-github-remote.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```
Lists the file tree via one GitHub API call, then fetches each scannable
file straight into memory over `raw.githubusercontent.com` — nothing
from the repo ever hits disk. This is the default recommendation for
checking an unfamiliar/untrusted repo before you'd otherwise `git clone`
it yourself.

Optional, for private repos or a higher API rate limit (60/hr → 5000/hr):
```bash
export GITHUB_TOKEN=<your-personal-access-token>   # e.g. GITHUB_TOKEN="$(gh auth token)"
./scan-github-remote.sh https://github.com/some-org/some-private-skill
```

All three support `-h`/`--help`, and drop into an interactive prompt
(asking for the path/URL, or `--help`) if run with no arguments from a
real terminal.

## Requirements

- `bash` (Git Bash or WSL on Windows — these are bash scripts, `.sh` files
  don't run directly from PowerShell or `cmd.exe`)
- `scan-github-skill.sh` also needs `git`
- `scan-github-remote.sh` also needs `curl` and a working `python3`
  (or `python`) — used for correctly parsing GitHub API JSON responses

## Testing

`test-fixtures/known-bad-skill/` (gitignored here, lives in its own repo
at `known-bad-skill-fixture`) is a synthetic, fully inert fixture that
trips every severity tier — every dangerous-looking line lives inside a
bash function that's never called, so it's safe to clone or execute by
accident. Use it as a regression check after touching `skill-scan-lib.sh`:

```bash
./scan-skill.sh path/to/known-bad-skill/   # expect: DANGEROUS, exit 2
```

## Limitations

- Regex-based detection can be evaded by a sufficiently obfuscated or
  cleverly-worded skill. Treat a SAFE/low-severity result as "nothing
  obvious found," not a guarantee.
- `scan-github-remote.sh` relies on the GitHub API; very large repos can
  get their file listing truncated (the script warns when this happens —
  fall back to `scan-github-skill.sh` for guaranteed full coverage).
- None of this replaces reading the skill's `SKILL.md` yourself, checking
  who published it, and — for anything you don't fully trust — running it
  in a sandbox first.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full file-by-file
walkthrough, and [docs/QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) for a
condensed command reference. A Hebrew usage guide is at
[docs/he/USAGE.he.md](docs/he/USAGE.he.md).

## License

[MIT](LICENSE)
