# push_to_github.ps1
# ATM10 CC:Tweaked Suite — GitHub Push Helper
#
# Run this script to push the project to GitHub and
# automatically update install.lua with your BASE_URL.
#
# HOW TO RUN:
#   Right-click this file → "Run with PowerShell"
#   OR open PowerShell in this folder and run:
#     .\push_to_github.ps1
#
# If you get an "execution policy" error, run this first:
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# ─────────────────────────────────────────────────────────────
# Config — paths
# ─────────────────────────────────────────────────────────────
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallFile = Join-Path $ScriptDir "atm10\install.lua"

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host "   ATM10 CC:Tweaked Suite — GitHub Push Helper" -ForegroundColor Cyan
    Write-Host "  ================================================" -ForegroundColor Yellow
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "  >> $Text" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [i]  $Text" -ForegroundColor Gray
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [!]  $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "  [X]  $Text" -ForegroundColor Red
}

function Pause-Exit {
    param([string]$Message = "Press Enter to exit...")
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Gray
    Read-Host | Out-Null
    exit
}

# ─────────────────────────────────────────────────────────────
# Check git is installed
# ─────────────────────────────────────────────────────────────
function Check-Git {
    Write-Step "Checking for git..."
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Err "git is not installed or not on your PATH."
        Write-Host ""
        Write-Host "  Install git from: https://git-scm.com/download/win" -ForegroundColor White
        Write-Host "  Then re-run this script." -ForegroundColor Gray
        Pause-Exit
    }
    $version = (git --version 2>&1)
    Write-OK $version
}

# ─────────────────────────────────────────────────────────────
# Get GitHub details (or read from existing remote)
# ─────────────────────────────────────────────────────────────
function Get-GitHubDetails {
    # Check if a remote already exists
    $existing = git remote get-url origin 2>$null
    if ($existing -and $existing -match "github\.com/([^/]+)/([^/\.]+)") {
        $u = $Matches[1]
        $r = $Matches[2]
        Write-Info "Found existing remote: $existing"
        Write-Host ""
        $confirm = Read-Host "  Use this remote? ($u / $r) [Y/n]"
        if ($confirm -eq "" -or $confirm -match "^[Yy]") {
            return @{ Username = $u; Repo = $r }
        }
    }

    Write-Host ""
    Write-Host "  Enter your GitHub details." -ForegroundColor White
    Write-Host "  The repo must already exist at github.com (create it first if needed)." -ForegroundColor Gray
    Write-Host ""

    $username = ""
    while ($username -eq "") {
        $username = (Read-Host "  GitHub username").Trim()
    }

    $repo = ""
    while ($repo -eq "") {
        $repo = (Read-Host "  Repository name (e.g. atm10-cctweaked)").Trim()
    }

    return @{ Username = $username; Repo = $repo }
}

# ─────────────────────────────────────────────────────────────
# Update BASE_URL in install.lua
# ─────────────────────────────────────────────────────────────
function Update-InstallLua {
    param([string]$Username, [string]$Repo)

    Write-Step "Updating install.lua BASE_URL..."

    if (-not (Test-Path $InstallFile)) {
        Write-Err "install.lua not found at: $InstallFile"
        return $false
    }

    $rawUrl  = "https://raw.githubusercontent.com/$Username/$Repo/main/atm10"
    $content = Get-Content $InstallFile -Raw

    # Replace any existing BASE_URL value
    $newContent = $content -replace '(?m)(^local BASE_URL\s*=\s*")[^"]*(")', "`${1}$rawUrl`$2"

    if ($newContent -eq $content) {
        Write-Warn "Could not find BASE_URL line to update. Check install.lua manually."
        Write-Info "Expected line:  local BASE_URL = `"...<url>...`""
        return $false
    }

    Set-Content -Path $InstallFile -Value $newContent -Encoding UTF8 -NoNewline
    Write-OK "BASE_URL set to: $rawUrl"
    return $true
}

# ─────────────────────────────────────────────────────────────
# Git init + remote setup (first time only)
# ─────────────────────────────────────────────────────────────
function Setup-GitRepo {
    param([string]$Username, [string]$Repo)

    Set-Location $ScriptDir

    # Init if needed
    if (-not (Test-Path (Join-Path $ScriptDir ".git"))) {
        Write-Step "Initialising git repository..."
        git init
        git branch -M main
        Write-OK "git repo initialised"
    }

    # Set or update remote
    $existing = git remote get-url origin 2>$null
    $targetUrl = "https://github.com/$Username/$Repo.git"

    if ($existing) {
        if ($existing -ne $targetUrl) {
            Write-Info "Updating remote origin to $targetUrl"
            git remote set-url origin $targetUrl
        }
    } else {
        Write-Step "Adding remote origin..."
        git remote add origin $targetUrl
        Write-OK "Remote set to $targetUrl"
    }
}

# ─────────────────────────────────────────────────────────────
# Commit and push
# ─────────────────────────────────────────────────────────────
function Commit-AndPush {
    Set-Location $ScriptDir

    Write-Step "Staging all files..."

    # Stage everything except data configs (they're runtime-generated)
    git add atm10/lib/
    git add atm10/hub.lua
    git add atm10/install.lua
    git add atm10/programs/
    git add atm10/blueprints/
    git add SETUP_AND_GUIDE.md
    git add push_to_github.ps1

    # Also add startup.lua if it exists in the repo
    if (Test-Path (Join-Path $ScriptDir "atm10\startup.lua")) {
        git add atm10/startup.lua
    }

    # Show what's staged
    Write-Host ""
    git status --short
    Write-Host ""

    # Check if there's anything to commit
    $staged = git diff --cached --name-only
    if (-not $staged) {
        Write-Warn "Nothing new to commit. All files are already up to date."
        return $true
    }

    # Get commit message
    $defaultMsg = "Update ATM10 CC:Tweaked suite"
    Write-Host "  Commit message (press Enter for default):" -ForegroundColor White
    Write-Host "  [$defaultMsg]" -ForegroundColor Gray
    $msg = (Read-Host "  >").Trim()
    if ($msg -eq "") { $msg = $defaultMsg }

    Write-Step "Committing..."
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Commit failed. You may need to set your git identity:"
        Write-Host "    git config --global user.email `"you@example.com`"" -ForegroundColor Yellow
        Write-Host "    git config --global user.name `"Your Name`"" -ForegroundColor Yellow
        return $false
    }
    Write-OK "Committed: $msg"

    Write-Step "Pushing to GitHub..."
    git push -u origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Push failed."
        Write-Host ""
        Write-Host "  Common causes:" -ForegroundColor White
        Write-Host "    - Repo doesn't exist yet on github.com" -ForegroundColor Gray
        Write-Host "    - Wrong username/repo name" -ForegroundColor Gray
        Write-Host "    - Not authenticated (see below)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  If this is your first push, GitHub may ask you to log in." -ForegroundColor White
        Write-Host "  Use a Personal Access Token (not your password):" -ForegroundColor White
        Write-Host "    github.com → Settings → Developer settings →" -ForegroundColor Gray
        Write-Host "    Personal access tokens → Tokens (classic) → Generate new token" -ForegroundColor Gray
        Write-Host "    Scopes needed: repo (check the top-level box)" -ForegroundColor Gray
        Write-Host "    Use this token as your password when prompted." -ForegroundColor Gray
        return $false
    }
    Write-OK "Pushed successfully!"
    return $true
}

# ─────────────────────────────────────────────────────────────
# Show final instructions
# ─────────────────────────────────────────────────────────────
function Show-NextSteps {
    param([string]$Username, [string]$Repo)

    $rawBase    = "https://raw.githubusercontent.com/$Username/$Repo/main/atm10"
    $repoUrl    = "https://github.com/$Username/$Repo"
    $hubRawUrl  = "$rawBase/hub.lua"

    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor Green
    Write-Host "   All done! Here's what to do next:" -ForegroundColor Green
    Write-Host "  ================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. Verify the files are live:" -ForegroundColor White
    Write-Host "     $hubRawUrl" -ForegroundColor Cyan
    Write-Host "     (open that URL in a browser — it should show Lua code)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Upload install.lua to Pastebin:" -ForegroundColor White
    Write-Host "     https://pastebin.com/  →  New Paste" -ForegroundColor Cyan
    Write-Host "     Copy the contents of:  atm10\install.lua" -ForegroundColor Gray
    Write-Host "     Set expiry: Never   Visibility: Public or Unlisted" -ForegroundColor Gray
    Write-Host "     Note your 8-character code from the URL" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. In-game on any CC:Tweaked computer:" -ForegroundColor White
    Write-Host "     pastebin get <YOUR_CODE> install" -ForegroundColor Yellow
    Write-Host "     install" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Your repo: $repoUrl" -ForegroundColor Gray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
Write-Header
Check-Git

$details = Get-GitHubDetails
$username = $details.Username
$repo     = $details.Repo

Update-InstallLua -Username $username -Repo $repo

Setup-GitRepo -Username $username -Repo $repo

$pushed = Commit-AndPush
if (-not $pushed) {
    Write-Host ""
    Write-Warn "Push did not complete. Fix the issue above and re-run."
    Pause-Exit "Press Enter to exit..."
}

Show-NextSteps -Username $username -Repo $repo

Pause-Exit "Press Enter to close..."
