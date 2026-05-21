# migrate.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `scripts/migrate.sh` on `feat/native-overhaul` so existing users who installed via the old `main` one-liner (curl|bash → Postgres + Next.js + tmux stack) can cleanly remove the heavy stack and prepare for the new native-only app — without losing their `~/MeetingScribe/` recordings.

**Architecture:** Single bash script, idempotent, interactive prompts modeled after `main:scripts/teardown.sh`. Detects an old install by presence of `~/Developer/meeting-scribe/apps/web` (web app dir is unique to `main`). Each cleanup step is independently skippable so partial-state machines (e.g. DB already dropped manually) still complete. Preserves user data (`~/MeetingScribe/`) and shared brew packages (`node`, `postgresql@17`, `ffmpeg`, `whisper-cpp`). Hosted at `raw.githubusercontent.com/scott-yj-yang/meeting-scribe/feat/native-overhaul/scripts/migrate.sh` until merged to main.

**Tech Stack:** Bash (POSIX-ish, targeting macOS default zsh users), shellcheck for static analysis. No new dependencies.

---

### Task 1: Create migrate.sh skeleton with shared helpers

**Files:**
- Create: `scripts/migrate.sh`

- [ ] **Step 1: Create scripts/migrate.sh with shebang, color helpers, and confirm() function**

```bash
#!/bin/bash
# MeetingScribe — Migration from main (full-stack) to feat/native-overhaul
#
# What this removes:
#   - tmux session 'meetingscribe' (old web server)
#   - ~/Applications/MeetingScribe.app and /Applications/MeetingScribe.app (old build)
#   - npm-linked `meetingctl` global symlink
#   - $BREW_PREFIX/bin/meetingscribe-update symlink (points at stale update.sh)
#   - Postgres database `meetingscribe`
#   - ~/Developer/meeting-scribe repo (the source tree from the old install)
#
# What this preserves:
#   - ~/MeetingScribe/        (user recordings — never touched)
#   - whisper-cpp + ffmpeg    (new app still uses them)
#   - node, postgresql@17     (user may use these for other projects)
#   - ~/.zshrc brew shellenv  (harmless to leave)
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/feat/native-overhaul/scripts/migrate.sh)"
#   # or locally:
#   bash scripts/migrate.sh
#   bash scripts/migrate.sh --all    # non-interactive, removes everything migratable

set -u

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
skip() { echo -e "  ${BLUE}-${NC} $1"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }
step() { echo -e "\n${BLUE}${BOLD}[$1]${NC} $2"; }

OLD_INSTALL_DIR="$HOME/Developer/meeting-scribe"
DB_NAME="meetingscribe"

if [[ "$(uname -m)" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

ALL=false
if [[ "${1:-}" == "--all" ]]; then ALL=true; fi

confirm() {
    if $ALL; then return 0; fi
    if [[ ! -t 0 ]]; then
        warn "Non-interactive shell — skipping: $1"
        return 1
    fi
    read -p "  $1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}
```

- [ ] **Step 2: Add the banner and detection guard at the bottom of the file**

```bash
echo -e "${YELLOW}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║  MeetingScribe Migration                          ║"
echo "  ║  main (Postgres + Next.js) → native-overhaul     ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ ! -d "$OLD_INSTALL_DIR/apps/web" ]] && \
   ! command -v meetingscribe-update &>/dev/null && \
   ! tmux has-session -t meetingscribe 2>/dev/null; then
    echo "  No old MeetingScribe install detected. Nothing to migrate."
    echo "  Proceed directly to the new native install."
    exit 0
fi

echo "  Detected old install. Recordings at ~/MeetingScribe/ will NOT be touched."
echo ""
```

- [ ] **Step 3: Verify shellcheck has no errors**

Run: `shellcheck scripts/migrate.sh`
Expected: No errors (`SC2034` warnings on unused color vars are tolerable since they will be used in later tasks).

If shellcheck isn't installed: `brew install shellcheck`.

- [ ] **Step 4: Smoke-test the no-op path**

Manually run on a machine **without** an old install:
```bash
bash scripts/migrate.sh
```
Expected output: `No old MeetingScribe install detected. Nothing to migrate.` and exit 0.

If you're on a machine *with* an old install, temporarily move it aside:
```bash
mv ~/Developer/meeting-scribe ~/Developer/meeting-scribe.bak
bash scripts/migrate.sh    # should exit cleanly
mv ~/Developer/meeting-scribe.bak ~/Developer/meeting-scribe
```

- [ ] **Step 5: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): scaffold migrate.sh with detection guard"
```

---

### Task 2: Stop the old tmux web server

**Files:**
- Modify: `scripts/migrate.sh` (append before the trailing detection guard exit-0 — append at end of file from now on; the guard `exit 0` only fires when nothing is detected)

- [ ] **Step 1: Append the tmux kill step**

```bash
step "1/6" "Stopping old web server..."
if tmux has-session -t meetingscribe 2>/dev/null; then
    tmux kill-session -t meetingscribe
    ok "Killed tmux session 'meetingscribe'"
else
    skip "No tmux session running"
fi

for port in 3000 3001; do
    PIDS=$(lsof -ti :$port 2>/dev/null || true)
    if [[ -n "$PIDS" ]]; then
        if confirm "Port $port is in use (PIDs: $PIDS). Kill?"; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
            ok "Freed port $port"
        else
            skip "Left port $port alone"
        fi
    fi
done
```

- [ ] **Step 2: Test with a real or fake tmux session**

If you have an old install running: just run `bash scripts/migrate.sh` and confirm the session is killed.

If not, simulate:
```bash
tmux new-session -d -s meetingscribe "sleep 60"
tmux has-session -t meetingscribe && echo "session exists"
bash scripts/migrate.sh    # answer 'n' to any port prompts
tmux has-session -t meetingscribe 2>/dev/null || echo "session gone"
```
Expected: `session exists` then `session gone`.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): kill old tmux session and free ports 3000/3001"
```

---

### Task 3: Remove old macOS app bundles

**Files:**
- Modify: `scripts/migrate.sh`

- [ ] **Step 1: Append the app removal step**

```bash
step "2/6" "Removing old MeetingScribe.app..."

osascript -e 'tell application "MeetingScribe" to quit' 2>/dev/null || true
sleep 1

REMOVED_APP=false
for APP_PATH in "$HOME/Applications/MeetingScribe.app" "/Applications/MeetingScribe.app"; do
    if [[ -d "$APP_PATH" ]]; then
        if confirm "Remove $APP_PATH?"; then
            rm -rf "$APP_PATH"
            ok "Removed $APP_PATH"
            REMOVED_APP=true
        else
            skip "Kept $APP_PATH"
        fi
    fi
done
if ! $REMOVED_APP && [[ ! -d "$HOME/Applications/MeetingScribe.app" ]] && [[ ! -d "/Applications/MeetingScribe.app" ]]; then
    skip "No MeetingScribe.app installed"
fi
```

- [ ] **Step 2: Test**

If you have an `.app` installed: run `bash scripts/migrate.sh`, answer `y`, confirm the bundle is gone.

If not: create a stub to verify the code path:
```bash
mkdir -p ~/Applications/MeetingScribe.app
bash scripts/migrate.sh    # answer 'y' to the .app prompt
[ -d ~/Applications/MeetingScribe.app ] && echo "FAIL" || echo "PASS"
```
Expected: `PASS`.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): remove old MeetingScribe.app from ~/Applications and /Applications"
```

---

### Task 4: Unlink global meetingctl CLI

**Files:**
- Modify: `scripts/migrate.sh`

- [ ] **Step 1: Append the CLI unlink step**

```bash
step "3/6" "Unlinking old meetingctl CLI..."
if command -v meetingctl &>/dev/null; then
    MEETINGCTL_PATH="$(command -v meetingctl)"
    if confirm "Unlink meetingctl ($MEETINGCTL_PATH)?"; then
        if [[ -d "$OLD_INSTALL_DIR/cli" ]]; then
            (cd "$OLD_INSTALL_DIR/cli" && npm unlink 2>/dev/null) || true
        fi
        rm -f "$MEETINGCTL_PATH" 2>/dev/null || sudo rm -f "$MEETINGCTL_PATH" 2>/dev/null || true
        if command -v meetingctl &>/dev/null; then
            warn "meetingctl still on PATH at $(command -v meetingctl) — remove manually"
        else
            ok "Unlinked meetingctl"
        fi
    else
        skip "Kept meetingctl"
    fi
else
    skip "meetingctl not on PATH"
fi
```

- [ ] **Step 2: Test**

If `meetingctl` is installed:
```bash
which meetingctl
bash scripts/migrate.sh    # answer 'y'
which meetingctl 2>/dev/null && echo "FAIL: still present" || echo "PASS"
```
Expected: `PASS`.

If not installed: just run migrate.sh; should print `meetingctl not on PATH` and continue.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): unlink global meetingctl symlink"
```

---

### Task 5: Remove stale meetingscribe-update symlink

**Files:**
- Modify: `scripts/migrate.sh`

This symlink is unique to main's setup.sh and points at the old `update.sh` which assumes the Postgres+Next.js layout. Leaving it would silently fail on future use.

- [ ] **Step 1: Append the symlink removal step**

```bash
step "4/6" "Removing stale meetingscribe-update symlink..."
UPDATE_SYMLINK="$BREW_PREFIX/bin/meetingscribe-update"
if [[ -L "$UPDATE_SYMLINK" ]] || [[ -f "$UPDATE_SYMLINK" ]]; then
    if confirm "Remove $UPDATE_SYMLINK?"; then
        rm -f "$UPDATE_SYMLINK" 2>/dev/null || sudo rm -f "$UPDATE_SYMLINK" 2>/dev/null || true
        if [[ ! -e "$UPDATE_SYMLINK" ]]; then
            ok "Removed $UPDATE_SYMLINK"
        else
            warn "Could not remove $UPDATE_SYMLINK — try: sudo rm $UPDATE_SYMLINK"
        fi
    else
        skip "Kept $UPDATE_SYMLINK"
    fi
else
    skip "No meetingscribe-update symlink"
fi
```

- [ ] **Step 2: Test**

Stub the symlink to verify the code path:
```bash
ln -sf /tmp/nonexistent $BREW_PREFIX/bin/meetingscribe-update 2>/dev/null || sudo ln -sf /tmp/nonexistent $BREW_PREFIX/bin/meetingscribe-update
bash scripts/migrate.sh    # answer 'y'
[ -e $BREW_PREFIX/bin/meetingscribe-update ] && echo "FAIL" || echo "PASS"
```
Expected: `PASS`.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): remove stale meetingscribe-update symlink"
```

---

### Task 6: Drop the Postgres database (opt-in)

**Files:**
- Modify: `scripts/migrate.sh`

- [ ] **Step 1: Append the DB drop step**

```bash
step "5/6" "PostgreSQL database 'meetingscribe'..."
export PATH="$BREW_PREFIX/opt/postgresql@17/bin:$PATH"
if command -v psql &>/dev/null && psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    warn "All server-side meeting data in the 'meetingscribe' DB will be permanently lost."
    warn "Your local recordings under ~/MeetingScribe/ are NOT affected."
    if confirm "Drop database '$DB_NAME'?"; then
        dropdb "$DB_NAME" 2>/dev/null && ok "Dropped database '$DB_NAME'" || warn "dropdb failed — run manually: dropdb $DB_NAME"
    else
        skip "Kept database '$DB_NAME'"
    fi
else
    skip "Database '$DB_NAME' not found (or psql unavailable)"
fi
```

- [ ] **Step 2: Test**

If postgres is running and the DB exists, just run migrate.sh.

If not, simulate:
```bash
brew services start postgresql@17
createdb meetingscribe 2>/dev/null
psql -l | grep meetingscribe
bash scripts/migrate.sh    # answer 'y'
psql -l | grep meetingscribe && echo "FAIL" || echo "PASS"
```
Expected: `PASS`.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): drop meetingscribe Postgres DB (opt-in)"
```

---

### Task 7: Remove the old repo (with branch-switch alternative)

**Files:**
- Modify: `scripts/migrate.sh`

Some users will want to keep `~/Developer/meeting-scribe` and just switch to the new branch (devs). Others want it gone. Offer both.

- [ ] **Step 1: Append the repo removal step**

```bash
step "6/6" "Old source tree at $OLD_INSTALL_DIR..."
if [[ -d "$OLD_INSTALL_DIR/.git" ]]; then
    echo "  Options:"
    echo "    1) Remove entirely (recommended if you don't develop MeetingScribe)"
    echo "    2) Switch to feat/native-overhaul branch (recommended for contributors)"
    echo "    3) Leave alone"
    if $ALL; then
        REPO_CHOICE=1
    else
        if [[ -t 0 ]]; then
            read -p "  Choose [1/2/3]: " -n 1 -r REPO_CHOICE
            echo
        else
            REPO_CHOICE=3
        fi
    fi
    case "$REPO_CHOICE" in
        1)
            rm -rf "$OLD_INSTALL_DIR"
            ok "Removed $OLD_INSTALL_DIR"
            ;;
        2)
            (cd "$OLD_INSTALL_DIR" && git fetch origin && git checkout feat/native-overhaul && git pull --ff-only) \
                && ok "Switched to feat/native-overhaul" \
                || warn "Branch switch failed — check $OLD_INSTALL_DIR/.git manually"
            ;;
        *)
            skip "Left $OLD_INSTALL_DIR in place"
            ;;
    esac
else
    skip "No git repo at $OLD_INSTALL_DIR"
fi
```

- [ ] **Step 2: Test the branch-switch path manually**

```bash
ls ~/Developer/meeting-scribe/.git
bash scripts/migrate.sh    # answer 2 at the repo prompt
(cd ~/Developer/meeting-scribe && git branch --show-current)
```
Expected: `feat/native-overhaul`.

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): remove or branch-switch old source tree"
```

---

### Task 8: Final summary + pointer to new install

**Files:**
- Modify: `scripts/migrate.sh`

- [ ] **Step 1: Append the final summary**

```bash
echo ""
echo -e "${GREEN}${BOLD}Migration complete.${NC}"
echo ""
echo "  Your recordings are safe at ~/MeetingScribe/"
echo ""
echo "  Next: install the new native MeetingScribe.app"
echo ""
echo "    Once the DMG is published, download from:"
echo "      https://github.com/scott-yj-yang/meeting-scribe/releases/latest"
echo ""
echo "    Until then (developer install):"
echo "      git clone https://github.com/scott-yj-yang/meeting-scribe.git \\"
echo "        --branch feat/native-overhaul ~/Developer/meeting-scribe"
echo "      cd ~/Developer/meeting-scribe && bash scripts/setup.sh"
echo ""
```

- [ ] **Step 2: Final shellcheck**

Run: `shellcheck scripts/migrate.sh`
Expected: clean (warnings on unused color vars are fine since they're meant for ergonomic future use).

- [ ] **Step 3: End-to-end manual test in a worktree or VM**

Ideal: run on a real machine that has an old install. Verify:
1. tmux session is gone
2. .app is removed from both `/Applications` and `~/Applications`
3. `command -v meetingctl` returns nothing
4. `command -v meetingscribe-update` returns nothing
5. `psql -l | grep meetingscribe` returns nothing
6. `~/Developer/meeting-scribe` is gone (or on feat/native-overhaul if you chose option 2)
7. `~/MeetingScribe/` is **still there** with original contents

Acceptable: if no machine has the full old install, test each step individually using the stub techniques from Tasks 2–7.

- [ ] **Step 4: Commit**

```bash
git add scripts/migrate.sh
git commit -m "feat(migrate): final summary pointing at new install path"
```

---

### Task 9: Document the migration in README and add an executable bit

**Files:**
- Modify: `README.md`
- Modify: `scripts/migrate.sh` (chmod)

- [ ] **Step 1: Make migrate.sh executable**

```bash
chmod +x scripts/migrate.sh
git update-index --chmod=+x scripts/migrate.sh
```

- [ ] **Step 2: Add a "Upgrading from main" section to README.md**

Insert after the existing `## Setup` section (around line 53):

```markdown
## Upgrading from the old (main branch) install

If you installed MeetingScribe before via the curl one-liner from `main`,
it set up Postgres, Next.js, and a tmux session. The native-overhaul
release replaces all of that with a single `.app`. To migrate cleanly:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/scott-yj-yang/meeting-scribe/feat/native-overhaul/scripts/migrate.sh)"
```

This interactively removes the old web server, app bundle, CLI symlink,
update symlink, and Postgres DB. **Your recordings under
`~/MeetingScribe/` are preserved.**

After migration, install the new app via [GitHub Releases](https://github.com/scott-yj-yang/meeting-scribe/releases/latest)
once the DMG is published.
```

- [ ] **Step 3: Commit**

```bash
git add scripts/migrate.sh README.md
git commit -m "docs(migrate): make migrate.sh executable and document migration path"
```

---

## Self-Review Checklist (done)

- **Coverage:** Every artifact identified in the discussion (tmux, .app, meetingctl, meetingscribe-update symlink, Postgres DB, old repo) has a removal task. Preserved items (`~/MeetingScribe/`, brew packages, `.zshrc`) are explicitly never touched.
- **Placeholders:** None.
- **Naming consistency:** `OLD_INSTALL_DIR`, `DB_NAME`, `BREW_PREFIX`, `UPDATE_SYMLINK` used consistently across tasks.
- **`set -u` safety:** All variable refs use `${var:-}` defaults where the variable may be unset (the `--all` arg).
