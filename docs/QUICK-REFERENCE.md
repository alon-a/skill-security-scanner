Quick reference for all three entry points (all live in [skills/skill-security-scanner/](../skills/skill-security-scanner/)):

**1. Local folder/file** — [scan-skill.sh](../skills/skill-security-scanner/scan-skill.sh)
```bash
./scan-skill.sh ~/path/to/some-skill/
./scan-skill.sh ~/path/to/some-skill/SKILL.md
```

**2. Remote repo, via temporary clone (git-based)** — [scan-github-skill.sh](../skills/skill-security-scanner/scan-github-skill.sh)
```bash
./scan-github-skill.sh https://github.com/some-user/some-skill

# monorepo, specific branch/subfolder:
./scan-github-skill.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```
Clones shallowly into a temp dir, scans, auto-deletes the clone on exit. Repo content briefly touches disk during the scan. Use this when the repo might be too large for the API to list in one page (`truncated` case).

**3. Remote repo, no clone at all** — [scan-github-remote.sh](../skills/skill-security-scanner/scan-github-remote.sh)
```bash
./scan-github-remote.sh https://github.com/some-user/some-skill

# monorepo, specific branch/subfolder — same URL syntax:
./scan-github-remote.sh https://github.com/user/monorepo/tree/dev/skills/my-skill
```
Fetches the file list via the GitHub API and each file's content via `raw.githubusercontent.com`, straight into memory — nothing is written to disk. Requires `curl` and a working `python3`/`python` (already present on your machine). This is the one to use by default for verifying an unfamiliar/untrusted repo before you'd otherwise `git clone` it.

**Optional for #3** — if you're hitting GitHub's 60-requests/hour unauthenticated limit, or need to scan a private repo:
```bash
export GITHUB_TOKEN=<your-personal-access-token>
./scan-github-remote.sh https://github.com/some-org/some-private-skill
```

All three print the same colored findings + summary and end with **exit code 0/1/2** for SAFE/SUSPICIOUS/DANGEROUS, so you can chain them, e.g.:
```bash
./scan-github-remote.sh https://github.com/some-user/some-skill && echo "safe to install"
```

If you'd rather have Claude Code drive it conversationally instead of running the script yourself, just say something like *"scan the GitHub repo https://github.com/some-user/some-skill without downloading it"* — it'll invoke `scan-github-remote.sh` and add its own contextual read of SKILL.md/prose on top (the regex pass is only step one, per the skill's own docs).