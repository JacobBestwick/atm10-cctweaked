#!/usr/bin/env bash
# push_to_github.sh
# ATM10 CC:Tweaked Suite — GitHub Push Script
#
# HOW TO RUN (Windows with Git installed):
#   Right-click this file → "Git Bash Here"  (or open Git Bash in this folder)
#   Then run:  bash push_to_github.sh
#
# On macOS/Linux:
#   chmod +x push_to_github.sh
#   ./push_to_github.sh

set -e  # stop on any error

REPO_URL="https://github.com/JacobBestwick/atm10-cctweaked.git"
USERNAME="JacobBestwick"
REPO_NAME="atm10-cctweaked"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${USERNAME}/${REPO_NAME}/${BRANCH}/atm10"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_FILE="${SCRIPT_DIR}/atm10/install.lua"

# ─────────────────────────────────────────────
# Colours
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # reset

ok()   { echo -e "  ${GREEN}[OK]${NC}  $1"; }
info() { echo -e "  ${GRAY}[i]${NC}   $1"; }
warn() { echo -e "  ${YELLOW}[!]${NC}   $1"; }
err()  { echo -e "  ${RED}[X]${NC}   $1"; }
step() { echo -e "\n  ${CYAN}>>${NC} ${BOLD}$1${NC}"; }

# ─────────────────────────────────────────────
# Banner
# ─────────────────────────────────────────────
clear
echo ""
echo -e "${YELLOW}  ================================================${NC}"
echo -e "${CYAN}   ATM10 CC:Tweaked Suite — GitHub Push Script${NC}"
echo -e "${YELLOW}  ================================================${NC}"
echo ""
echo -e "  Repo: ${CYAN}${REPO_URL}${NC}"
echo ""

# ─────────────────────────────────────────────
# Check git
# ─────────────────────────────────────────────
step "Checking for git..."
if ! command -v git &>/dev/null; then
  err "git is not installed."
  echo ""
  echo "  Download from: https://git-scm.com/download/win"
  echo "  (Git Bash is included with the Windows installer)"
  exit 1
fi
ok "$(git --version)"

# ─────────────────────────────────────────────
# Update BASE_URL in install.lua
# ─────────────────────────────────────────────
step "Updating install.lua BASE_URL..."

if [ ! -f "$INSTALL_FILE" ]; then
  err "install.lua not found at: $INSTALL_FILE"
  exit 1
fi

# Replace the BASE_URL line (works on both macOS sed and GNU sed)
if grep -q 'local BASE_URL' "$INSTALL_FILE"; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|^local BASE_URL = .*|local BASE_URL = \"${BASE_URL}\"|" "$INSTALL_FILE"
  else
    sed -i "s|^local BASE_URL = .*|local BASE_URL = \"${BASE_URL}\"|" "$INSTALL_FILE"
  fi
  ok "BASE_URL set to: ${BASE_URL}"
else
  warn "Could not find BASE_URL line in install.lua — check it manually."
fi

# ─────────────────────────────────────────────
# Git init (if needed)
# ─────────────────────────────────────────────
cd "$SCRIPT_DIR"

if [ ! -d ".git" ]; then
  step "Initialising git repository..."
  git init
  git branch -M "$BRANCH"
  ok "Git repo initialised"
fi

# ─────────────────────────────────────────────
# Fix nested .git (submodule problem)
# If atm10/ has its own .git folder, git treats
# it as a submodule and refuses to stage its files.
# Remove the nested .git so atm10/ is a plain folder.
# ─────────────────────────────────────────────
step "Checking for nested git repos..."
if [ -d "${SCRIPT_DIR}/atm10/.git" ]; then
  warn "Found .git inside atm10/ — removing it (was causing submodule error)"
  rm -rf "${SCRIPT_DIR}/atm10/.git"
  ok "Removed atm10/.git"
  # Also deregister it from the index if it was ever tracked as a submodule
  git rm --cached atm10 2>/dev/null || true
  info "atm10/ is now a regular folder"
else
  ok "No nested .git found"
fi

# ─────────────────────────────────────────────
# Set remote
# ─────────────────────────────────────────────
step "Setting remote origin..."
if git remote get-url origin &>/dev/null; then
  CURRENT=$(git remote get-url origin)
  if [ "$CURRENT" != "$REPO_URL" ]; then
    info "Updating remote from: $CURRENT"
    git remote set-url origin "$REPO_URL"
  fi
  ok "Remote: $REPO_URL"
else
  git remote add origin "$REPO_URL"
  ok "Remote added: $REPO_URL"
fi

# ─────────────────────────────────────────────
# Stage files
# ─────────────────────────────────────────────
step "Staging files..."

git add atm10/lib/
git add atm10/hub.lua
git add atm10/install.lua
git add atm10/programs/
git add atm10/blueprints/
git add SETUP_AND_GUIDE.md
git add push_to_github.sh

# Include startup.lua only if it exists in the project folder
[ -f "atm10/startup.lua" ] && git add atm10/startup.lua

echo ""
git status --short
echo ""

# Check there's anything to commit
if git diff --cached --quiet; then
  warn "Nothing new to commit — all files are already up to date."
  echo ""
  echo -e "  ${GRAY}If you expected changes, make sure you saved your files first.${NC}"
  echo ""
  exit 0
fi

# ─────────────────────────────────────────────
# Commit message
# ─────────────────────────────────────────────
DEFAULT_MSG="Update ATM10 CC:Tweaked suite"
echo -e "  ${BOLD}Commit message${NC} (press Enter for default):"
echo -e "  ${GRAY}[${DEFAULT_MSG}]${NC}"
read -rp "  > " COMMIT_MSG
COMMIT_MSG="${COMMIT_MSG:-$DEFAULT_MSG}"

step "Committing..."
if ! git commit -m "$COMMIT_MSG"; then
  err "Commit failed. You may need to set your git identity:"
  echo ""
  echo "    git config --global user.email \"you@example.com\""
  echo "    git config --global user.name \"Your Name\""
  exit 1
fi
ok "Committed: $COMMIT_MSG"

# ─────────────────────────────────────────────
# Push
# ─────────────────────────────────────────────
step "Pushing to GitHub..."
if ! git push -u origin "$BRANCH"; then
  err "Push failed."
  echo ""
  echo -e "  ${BOLD}Common causes:${NC}"
  echo "    - Repo doesn't exist yet on github.com (create it first)"
  echo "    - Not authenticated"
  echo ""
  echo -e "  ${BOLD}Authentication (first push):${NC}"
  echo "    GitHub no longer accepts passwords. Use a Personal Access Token:"
  echo "    github.com → Settings → Developer settings →"
  echo "    Personal access tokens → Tokens (classic) → Generate new token"
  echo "    Tick the 'repo' scope. Paste the token as your password."
  exit 1
fi
ok "Pushed to ${REPO_URL}"

# ─────────────────────────────────────────────
# Done — next steps
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}  ================================================${NC}"
echo -e "${GREEN}   Done! Next steps:${NC}"
echo -e "${GREEN}  ================================================${NC}"
echo ""
echo -e "  ${BOLD}1. Verify the files are live:${NC}"
echo -e "     ${CYAN}https://raw.githubusercontent.com/${USERNAME}/${REPO_NAME}/main/atm10/hub.lua${NC}"
echo "     (open that URL in a browser — should show Lua code)"
echo ""
echo -e "  ${BOLD}2. Upload install.lua to Pastebin:${NC}"
echo -e "     ${CYAN}https://pastebin.com/${NC}  →  New Paste"
echo "     Copy contents of:  atm10/install.lua"
echo "     Expiry: Never   Visibility: Public or Unlisted"
echo "     Note the 8-character code in the URL"
echo ""
echo -e "  ${BOLD}3. In-game on any CC:Tweaked computer:${NC}"
echo -e "     ${YELLOW}pastebin get <YOUR_CODE> install${NC}"
echo -e "     ${YELLOW}install${NC}"
echo ""
