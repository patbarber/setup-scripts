#!/usr/bin/env bash
#
# check-devtools.sh — survey installed developer tooling.
#
# Cross-platform: macOS and Linux. Platform-specific checks (Xcode, Homebrew,
# apt/dnf/pacman, ...) are skipped automatically on the platforms where they
# do not apply.
#
# Compatible with bash 3.2 (the version macOS ships) — no associative arrays.
#
# Usage: ./check-devtools.sh [options]
#   -c, --category NAME   Only run this category (repeatable)
#   -l, --list            List category names and exit
#   -m, --missing         Only show tools that are NOT installed
#   -i, --installed       Only show tools that ARE installed
#   -j, --json            Emit JSON instead of a table
#       --no-color        Disable ANSI colour
#       --no-versions     Skip version probing (much faster)
#       --strict          Exit non-zero if anything is missing
#       --install         After the survey, walk through missing tools
#                         category by category and install the ones you pick
#       --dry-run         Like --install, but print the commands instead of
#                         running them
#   -y, --yes             Skip the final confirmation prompt (with --install)
#   -h, --help            Show this help

set -u

VERSION="1.0.0"

# ---------------------------------------------------------------- options ---

ONLY_CATEGORIES=""
LIST_ONLY=0
SHOW="all"        # all | missing | installed
FORMAT="table"    # table | json
USE_COLOR="auto"
PROBE_VERSIONS=1
STRICT=0
INSTALL_MODE=0
DRY_RUN=0
ASSUME_YES=0

usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--category)  ONLY_CATEGORIES="$ONLY_CATEGORIES $2"; shift 2 ;;
    -l|--list)      LIST_ONLY=1; shift ;;
    -m|--missing)   SHOW="missing"; shift ;;
    -i|--installed) SHOW="installed"; shift ;;
    -j|--json)      FORMAT="json"; shift ;;
    --no-color)     USE_COLOR="never"; shift ;;
    --no-versions)  PROBE_VERSIONS=0; shift ;;
    --strict)       STRICT=1; shift ;;
    --install)      INSTALL_MODE=1; shift ;;
    --dry-run)      INSTALL_MODE=1; DRY_RUN=1; shift ;;
    -y|--yes)       ASSUME_YES=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    -V|--version)   echo "check-devtools.sh $VERSION"; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ----------------------------------------------------------------- colour ---

if [ "$USE_COLOR" = "never" ] || [ ! -t 1 ] || [ "$FORMAT" = "json" ]; then
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""
else
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m';   C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
fi

# --------------------------------------------------------------- platform ---

UNAME_S="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME_S" in
  Darwin) PLATFORM="mac" ;;
  Linux)  PLATFORM="linux" ;;
  *)      PLATFORM="other" ;;
esac
ARCH="$(uname -m 2>/dev/null || echo unknown)"

os_description() {
  if [ "$PLATFORM" = "mac" ]; then
    printf '%s %s (%s)' \
      "$(sw_vers -productName 2>/dev/null || echo macOS)" \
      "$(sw_vers -productVersion 2>/dev/null || echo '?')" \
      "$(sw_vers -buildVersion 2>/dev/null || echo '?')"
  elif [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
  else
    printf '%s %s' "$UNAME_S" "$(uname -r 2>/dev/null || echo '?')"
  fi
}

# ------------------------------------------------------------------ table ---
#
# One record per line:  category | label | binary | platform | version_cmd
#
#   platform     all | mac | linux
#   version_cmd  shell snippet whose stdout is the version string.
#                Empty means: "$BIN" --version
#
# $BIN is exported into the snippet as the resolved absolute path.

TOOLS='
runtimes|Node.js|node|all|
runtimes|Deno|deno|all|
runtimes|Bun|bun|all|
runtimes|Python 3|python3|all|
runtimes|Ruby|ruby|all|
runtimes|Go|go|all|"$BIN" version
runtimes|Rust (rustc)|rustc|all|
runtimes|Java (JRE)|java|all|"$BIN" -version 2>&1
runtimes|Java (JDK)|javac|all|"$BIN" -version 2>&1
runtimes|Kotlin|kotlin|all|
runtimes|Scala|scala|all|
runtimes|Swift|swift|all|"$BIN" --version 2>&1
runtimes|PHP|php|all|
runtimes|Perl|perl|all|"$BIN" -v 2>&1 | grep -m1 -o "v[0-9][0-9.]*"
runtimes|Lua|lua|all|"$BIN" -v 2>&1
runtimes|LuaJIT|luajit|all|"$BIN" -v 2>&1
runtimes|.NET|dotnet|all|
runtimes|Elixir|elixir|all|
runtimes|Erlang|erl|all|"$BIN" -noshell -eval "io:format(erlang:system_info(otp_release)),halt()."
runtimes|Zig|zig|all|"$BIN" version
runtimes|Julia|julia|all|
runtimes|R|Rscript|all|"$BIN" --version 2>&1
runtimes|Haskell (GHC)|ghc|all|
runtimes|Dart|dart|all|
runtimes|Crystal|crystal|all|
runtimes|Nim|nim|all|"$BIN" --version

pkgmgr|npm|npm|all|
pkgmgr|pnpm|pnpm|all|
pkgmgr|Yarn|yarn|all|
pkgmgr|pip|pip3|all|
pkgmgr|uv|uv|all|
pkgmgr|pipx|pipx|all|
pkgmgr|Poetry|poetry|all|
pkgmgr|RubyGems|gem|all|
pkgmgr|Bundler|bundle|all|
pkgmgr|Cargo|cargo|all|
pkgmgr|Composer|composer|all|"$BIN" --version --no-plugins 2>/dev/null
pkgmgr|CocoaPods|pod|mac|
pkgmgr|Maven|mvn|all|"$BIN" -v 2>&1
pkgmgr|Gradle|gradle|all|"$BIN" -v 2>&1 | grep -i "^Gradle"
pkgmgr|Homebrew|brew|mac|
pkgmgr|Homebrew (linuxbrew)|brew|linux|
pkgmgr|apt|apt|linux|
pkgmgr|dnf|dnf|linux|
pkgmgr|pacman|pacman|linux|"$BIN" --version 2>&1 | grep -m1 Pacman
pkgmgr|zypper|zypper|linux|
pkgmgr|apk|apk|linux|"$BIN" --version 2>&1
pkgmgr|snap|snap|linux|"$BIN" version 2>&1 | head -1
pkgmgr|flatpak|flatpak|linux|
pkgmgr|mas (Mac App Store)|mas|mac|

versionmgr|nvm|nvm|all|__nvm_version
versionmgr|fnm|fnm|all|
versionmgr|Volta|volta|all|
versionmgr|asdf|asdf|all|
versionmgr|mise|mise|all|
versionmgr|pyenv|pyenv|all|
versionmgr|rbenv|rbenv|all|
versionmgr|rustup|rustup|all|
versionmgr|SDKMAN|sdk|all|__sdkman_version
versionmgr|jenv|jenv|all|
versionmgr|direnv|direnv|all|

buildtools|C compiler (cc)|cc|all|"$BIN" --version 2>&1
buildtools|clang|clang|all|
buildtools|gcc|gcc|all|
buildtools|g++|g++|all|
buildtools|make|make|all|"$BIN" --version 2>&1
buildtools|cmake|cmake|all|"$BIN" --version 2>&1
buildtools|ninja|ninja|all|
buildtools|Bazel|bazel|all|
buildtools|just|just|all|
buildtools|pkg-config|pkg-config|all|
buildtools|autoconf|autoconf|all|"$BIN" --version 2>&1
buildtools|gdb|gdb|all|"$BIN" --version 2>&1
buildtools|lldb|lldb|all|"$BIN" --version 2>&1
buildtools|protoc|protoc|all|

mobile|Xcode (xcodebuild)|xcodebuild|mac|"$BIN" -version 2>&1 | tr "\n" " "
mobile|Xcode CLT (xcrun)|xcrun|mac|"$BIN" --version 2>&1
mobile|adb (Android)|adb|all|"$BIN" --version 2>&1 | head -1
mobile|Flutter|flutter|all|"$BIN" --version 2>&1 | head -1
mobile|EAS CLI|eas|all|
mobile|Fastlane|fastlane|all|"$BIN" --version 2>&1 | grep -m1 "fastlane "

cloud|Docker|docker|all|
cloud|Docker Compose|docker|all|"$BIN" compose version 2>&1 | head -1
cloud|Podman|podman|all|
cloud|Colima|colima|mac|
cloud|kubectl|kubectl|all|"$BIN" version --client 2>&1 | head -1
cloud|Helm|helm|all|"$BIN" version --short 2>&1
cloud|k9s|k9s|all|"$BIN" version -s 2>&1 | head -3 | tr "\n" " "
cloud|minikube|minikube|all|"$BIN" version --short 2>&1
cloud|Terraform|terraform|all|"$BIN" version 2>&1 | head -1
cloud|OpenTofu|tofu|all|"$BIN" version 2>&1 | head -1
cloud|Pulumi|pulumi|all|
cloud|Ansible|ansible|all|"$BIN" --version 2>&1 | head -1
cloud|Vagrant|vagrant|all|
cloud|AWS CLI|aws|all|
cloud|AWS CDK|cdk|all|
cloud|Azure CLI|az|all|"$BIN" version 2>&1 | head -1
cloud|gcloud|gcloud|all|"$BIN" --version 2>&1 | head -1
cloud|Firebase CLI|firebase|all|
cloud|Wrangler (Cloudflare)|wrangler|all|
cloud|Vercel|vercel|all|
cloud|Netlify|netlify|all|
cloud|Supabase|supabase|all|
cloud|Fly.io|flyctl|all|"$BIN" version 2>&1
cloud|Heroku|heroku|all|
cloud|doctl|doctl|all|"$BIN" version 2>&1 | head -1
cloud|Tailscale|tailscale|all|"$BIN" version 2>&1 | head -1
cloud|ngrok|ngrok|all|"$BIN" version 2>&1
cloud|cloudflared|cloudflared|all|"$BIN" --version 2>&1

data|sqlite3|sqlite3|all|"$BIN" --version 2>&1
data|psql (Postgres)|psql|all|
data|mysql|mysql|all|
data|redis-cli|redis-cli|all|
data|mongosh|mongosh|all|
data|DuckDB|duckdb|all|
data|dbt|dbt|all|"$BIN" --version 2>&1 | head -1
data|Turso|turso|all|

vcs|git|git|all|
vcs|git-lfs|git-lfs|all|"$BIN" version 2>&1
vcs|GitHub CLI|gh|all|"$BIN" --version 2>&1 | head -1
vcs|GitLab CLI|glab|all|"$BIN" --version 2>&1 | head -1
vcs|lazygit|lazygit|all|"$BIN" --version 2>&1
vcs|Mercurial|hg|all|"$BIN" --version 2>&1 | head -1
vcs|pre-commit|pre-commit|all|

editors|Neovim|nvim|all|"$BIN" --version 2>&1 | head -1
editors|Vim|vim|all|"$BIN" --version 2>&1 | head -1
editors|Emacs|emacs|all|"$BIN" --version 2>&1 | head -1
editors|VS Code|code|all|"$BIN" --version 2>&1 | head -1
editors|Cursor|cursor|all|"$BIN" --version 2>&1 | head -1
editors|Zed|zed|all|
editors|tmux|tmux|all|"$BIN" -V
editors|Claude Code|claude|all|

cli|ripgrep|rg|all|
cli|fd|fd|all|
cli|fzf|fzf|all|
cli|bat|bat|all|"$BIN" --version 2>&1 | head -1
cli|eza|eza|all|
cli|lsd|lsd|all|
cli|zoxide|zoxide|all|
cli|jq|jq|all|
cli|yq|yq|all|"$BIN" --version 2>&1
cli|htop|htop|all|"$BIN" --version 2>&1 | head -1
cli|btop|btop|all|"$BIN" --version 2>&1 | head -1
cli|tree|tree|all|"$BIN" --version 2>&1 | head -1
cli|curl|curl|all|"$BIN" --version 2>&1 | head -1
cli|wget|wget|all|"$BIN" --version 2>&1 | head -1
cli|httpie|http|all|
cli|watchman|watchman|all|
cli|GnuPG|gpg|all|"$BIN" --version 2>&1 | head -1
cli|OpenSSL|openssl|all|"$BIN" version
cli|mkcert|mkcert|all|"$BIN" -version 2>&1
cli|sops|sops|all|"$BIN" --version 2>&1 | head -1
cli|ffmpeg|ffmpeg|all|"$BIN" -version 2>&1 | head -1
cli|ImageMagick|magick|all|"$BIN" --version 2>&1 | head -1
cli|pandoc|pandoc|all|"$BIN" --version 2>&1 | head -1
cli|tesseract|tesseract|all|"$BIN" --version 2>&1 | head -1

quality|shellcheck|shellcheck|all|"$BIN" --version 2>&1 | grep -m1 version:
quality|shfmt|shfmt|all|
quality|TypeScript (tsc)|tsc|all|"$BIN" --version 2>&1
quality|ESLint|eslint|all|
quality|Prettier|prettier|all|
quality|ruff|ruff|all|
quality|black|black|all|"$BIN" --version 2>&1 | head -1
quality|mypy|mypy|all|
quality|hadolint|hadolint|all|"$BIN" --version 2>&1
quality|trivy|trivy|all|"$BIN" --version 2>&1 | head -1
quality|semgrep|semgrep|all|"$BIN" --version 2>&1 | head -1
'

# --------------------------------------------------- special-case probes ---
# Some things are shell functions or sourced scripts, not binaries on PATH.

__nvm_version() {
  if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
    # shellcheck disable=SC1090
    . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" >/dev/null 2>&1 && nvm --version 2>/dev/null
  fi
}

__sdkman_version() {
  if [ -s "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh" ]; then
    grep -m1 -o '[0-9][0-9.]*' "${SDKMAN_DIR:-$HOME/.sdkman}/var/version" 2>/dev/null \
      || echo "installed"
  fi
}

# ------------------------------------------------------------- utilities ---

# Trim, collapse whitespace, drop control chars, truncate.
clean_version() {
  tr '\n' ' ' \
    | tr -d '\r' \
    | sed -e 's/[[:cntrl:]]//g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//' \
    | cut -c1-72
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

category_title() {
  case "$1" in
    runtimes)   echo "Language runtimes & SDKs" ;;
    pkgmgr)     echo "Package managers" ;;
    versionmgr) echo "Version managers" ;;
    buildtools) echo "Build & compile toolchain" ;;
    mobile)     echo "Mobile & native" ;;
    cloud)      echo "Cloud, containers & infra" ;;
    data)       echo "Databases & data" ;;
    vcs)        echo "Version control" ;;
    editors)    echo "Editors & terminal" ;;
    cli)        echo "CLI utilities" ;;
    quality)    echo "Linters, formatters & scanners" ;;
    *)          echo "$1" ;;
  esac
}

CATEGORY_ORDER="runtimes pkgmgr versionmgr buildtools mobile cloud data vcs editors cli quality"

if [ "$LIST_ONLY" -eq 1 ]; then
  for c in $CATEGORY_ORDER; do
    printf '%-12s %s\n' "$c" "$(category_title "$c")"
  done
  exit 0
fi

wanted_category() {
  [ -z "$ONLY_CATEGORIES" ] && return 0
  for c in $ONLY_CATEGORIES; do
    [ "$c" = "$1" ] && return 0
  done
  return 1
}

applies_here() {
  case "$1" in
    all)   return 0 ;;
    "$PLATFORM") return 0 ;;
    *)     return 1 ;;
  esac
}

# -------------------------------------------------------------- the check ---

TOTAL=0
FOUND=0
MISSING=0
BROKEN=0
MISSING_LIST=""
BROKEN_LIST=""
MISSING_RECORDS=""

# Buffer table rows per category so we can skip empty categories.
run_category() {
  cat_key="$1"
  rows=""
  cat_total=0
  cat_found=0

  # Read records for this category.
  while IFS='|' read -r rec_cat label bin plat vcmd; do
    [ -z "${rec_cat:-}" ] && continue
    [ "$rec_cat" != "$cat_key" ] && continue
    applies_here "$plat" || continue

    cat_total=$((cat_total + 1))
    TOTAL=$((TOTAL + 1))

    path=""
    version=""
    ok=0

    case "$vcmd" in
      __nvm_version|__sdkman_version)
        version="$("$vcmd" 2>/dev/null | clean_version)"
        if [ -n "$version" ]; then
          ok=1
          path="${NVM_DIR:-$HOME/.nvm}"
          [ "$vcmd" = "__sdkman_version" ] && path="${SDKMAN_DIR:-$HOME/.sdkman}"
        fi
        ;;
      *)
        path="$(command -v "$bin" 2>/dev/null || true)"
        if [ -n "$path" ]; then
          ok=1
          if [ "$PROBE_VERSIONS" -eq 1 ]; then
            BIN="$path"
            export BIN
            if [ -n "$vcmd" ]; then
              raw="$(eval "$vcmd" 2>/dev/null)"; rc=$?
            else
              raw="$("$path" --version 2>/dev/null)"; rc=$?
            fi
            version="$(printf '%s' "$raw" | clean_version)"
            [ -z "$version" ] && version="(version unknown)"
            # A binary that exists but cannot run — e.g. the macOS `java` shim
            # with no JDK behind it — is worse than useless. Flag it.
            if [ "$rc" -ne 0 ]; then
              ok=2
            fi
          fi
        fi
        ;;
    esac

    if [ "$ok" -eq 1 ]; then
      cat_found=$((cat_found + 1)); FOUND=$((FOUND + 1))
      [ "$SHOW" = "missing" ] && continue
      mark="${C_GREEN}✓${C_RESET}"
    elif [ "$ok" -eq 2 ]; then
      BROKEN=$((BROKEN + 1))
      BROKEN_LIST="$BROKEN_LIST $label"
      MISSING_RECORDS="$MISSING_RECORDS$cat_key|$label|$bin|broken
"
      [ "$SHOW" = "installed" ] && continue
      mark="${C_YELLOW}!${C_RESET}"
      version="on PATH but not runnable — ${version}"
    else
      MISSING=$((MISSING + 1))
      MISSING_LIST="$MISSING_LIST $label"
      MISSING_RECORDS="$MISSING_RECORDS$cat_key|$label|$bin|missing
"
      [ "$SHOW" = "installed" ] && continue
      mark="${C_RED}✗${C_RESET}"
    fi

    if [ "$FORMAT" = "json" ]; then
      rows="$rows{\"category\":\"$(json_escape "$cat_key")\",\"name\":\"$(json_escape "$label")\",\"command\":\"$(json_escape "$bin")\",\"installed\":$([ "$ok" -ne 0 ] && echo true || echo false),\"runnable\":$([ "$ok" -eq 1 ] && echo true || echo false),\"path\":\"$(json_escape "$path")\",\"version\":\"$(json_escape "$version")\"}
"
    else
      if [ "$ok" -ne 0 ]; then
        rows="$rows$(printf '  %b %-24s %s%s%s\n' "$mark" "$label" "$C_DIM" "$version" "$C_RESET")
"
      else
        rows="$rows$(printf '  %b %-24s %s%s%s\n' "$mark" "$label" "$C_DIM" "not installed" "$C_RESET")
"
      fi
    fi
  done <<EOF
$(printf '%s\n' "$TOOLS")
EOF

  [ -z "$rows" ] && return 0

  if [ "$FORMAT" = "json" ]; then
    printf '%s' "$rows"
  else
    printf '\n%s%s%s %s(%d/%d)%s\n' \
      "$C_BOLD$C_BLUE" "$(category_title "$cat_key")" "$C_RESET" \
      "$C_DIM" "$cat_found" "$cat_total" "$C_RESET"
    printf '%s' "$rows"
  fi
}

# ------------------------------------------------------------ extra notes ---

platform_notes() {
  printf '\n%s%s%s\n' "$C_BOLD$C_BLUE" "Environment details" "$C_RESET"

  if [ "$PLATFORM" = "mac" ]; then
    if command -v xcode-select >/dev/null 2>&1; then
      dev="$(xcode-select -p 2>/dev/null || echo 'not configured')"
      printf '  %-24s %s%s%s\n' "Xcode developer dir" "$C_DIM" "$dev" "$C_RESET"
    fi
    if command -v xcrun >/dev/null 2>&1; then
      sims="$(xcrun simctl list runtimes 2>/dev/null | grep -c 'iOS' || echo 0)"
      printf '  %-24s %s%s%s\n' "iOS simulator runtimes" "$C_DIM" "$sims" "$C_RESET"
    fi
  fi

  if [ "$PLATFORM" = "linux" ]; then
    if [ -r /proc/version ]; then
      printf '  %-24s %s%s%s\n' "Kernel" "$C_DIM" "$(uname -r)" "$C_RESET"
    fi
    if grep -qi microsoft /proc/version 2>/dev/null; then
      printf '  %-24s %s%s%s\n' "WSL" "$C_DIM" "yes" "$C_RESET"
    fi
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      printf '  %-24s %s%s%s\n' "Display server" "$C_DIM" \
        "${WAYLAND_DISPLAY:+wayland }${DISPLAY:+x11}" "$C_RESET"
    fi
  fi

  # Android SDK — same idea on both platforms, different default location.
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
             "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [ -n "$sdk" ] && [ -d "$sdk" ]; then
      plats="$(ls "$sdk/platforms" 2>/dev/null | tr '\n' ' ')"
      printf '  %-24s %s%s%s\n' "Android SDK" "$C_DIM" "$sdk" "$C_RESET"
      [ -n "$plats" ] && printf '  %-24s %s%s%s\n' "  platforms" "$C_DIM" "$plats" "$C_RESET"
      break
    fi
  done

  # Installed Node versions, whichever manager is in play.
  if [ -d "${NVM_DIR:-$HOME/.nvm}/versions/node" ]; then
    vers="$(ls "${NVM_DIR:-$HOME/.nvm}/versions/node" 2>/dev/null | tr '\n' ' ')"
    printf '  %-24s %s%s%s\n' "nvm node versions" "$C_DIM" "$vers" "$C_RESET"
  fi

  # .NET SDKs
  if command -v dotnet >/dev/null 2>&1; then
    sdks="$(dotnet --list-sdks 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
    [ -n "$sdks" ] && printf '  %-24s %s%s%s\n' ".NET SDKs" "$C_DIM" "$sdks" "$C_RESET"
  fi

  # Global npm packages
  if command -v npm >/dev/null 2>&1; then
    globals="$(npm ls -g --depth=0 --parseable 2>/dev/null \
      | tail -n +2 | sed 's|.*/node_modules/||' | tr '\n' ' ')"
    [ -n "$globals" ] && printf '  %-24s %s%s%s\n' "npm globals" "$C_DIM" "$globals" "$C_RESET"
  fi
}


# =========================================================================== #
#                            GUIDED INSTALLATION                              #
# =========================================================================== #
#
# Recipes map a binary to a package name per package manager. One line per
# tool:  bin|mgr=pkg mgr=pkg ...
#
# Recognised managers, in the order they are preferred:
#   brew  cask  apt  dnf  pacman  zypper  apk  npm  cargo  pipx  gem  go
#
# `cask` is macOS-only (GUI apps). Anything with no recipe is reported as
# "no automated recipe" rather than silently skipped.

RECIPES='
node|brew=node apt=nodejs dnf=nodejs pacman=nodejs apk=nodejs
deno|brew=deno pacman=deno
bun|brew=bun
python3|brew=python apt=python3 dnf=python3 pacman=python apk=python3
ruby|brew=ruby apt=ruby-full dnf=ruby pacman=ruby apk=ruby
go|brew=go apt=golang dnf=golang pacman=go apk=go
kotlin|brew=kotlin pacman=kotlin
scala|brew=scala pacman=scala
php|brew=php apt=php dnf=php pacman=php apk=php
lua|brew=lua apt=lua5.4 dnf=lua pacman=lua apk=lua5.4
luajit|brew=luajit apt=luajit dnf=luajit pacman=luajit
elixir|brew=elixir apt=elixir dnf=elixir pacman=elixir apk=elixir
erl|brew=erlang apt=erlang dnf=erlang pacman=erlang
zig|brew=zig pacman=zig apk=zig
julia|brew=julia pacman=julia
Rscript|brew=r apt=r-base dnf=R pacman=r
ghc|brew=ghc apt=ghc pacman=ghc
crystal|brew=crystal pacman=crystal
nim|brew=nim apt=nim dnf=nim pacman=nim

pnpm|brew=pnpm npm=pnpm
yarn|brew=yarn npm=yarn
pip3|apt=python3-pip dnf=python3-pip pacman=python-pip apk=py3-pip
pipx|brew=pipx apt=pipx dnf=pipx pacman=python-pipx
poetry|brew=poetry pipx=poetry
bundle|gem=bundler
composer|brew=composer apt=composer dnf=composer pacman=composer
pod|gem=cocoapods
mvn|brew=maven apt=maven dnf=maven pacman=maven
gradle|brew=gradle apt=gradle dnf=gradle pacman=gradle
flatpak|apt=flatpak dnf=flatpak pacman=flatpak

fnm|brew=fnm cargo=fnm
volta|brew=volta
asdf|brew=asdf
mise|brew=mise cargo=mise
pyenv|brew=pyenv
rbenv|brew=rbenv
jenv|brew=jenv
direnv|brew=direnv apt=direnv dnf=direnv pacman=direnv apk=direnv

gcc|apt=build-essential dnf=gcc pacman=gcc apk=build-base
g++|apt=build-essential dnf=gcc-c++ pacman=gcc apk=build-base
make|apt=make dnf=make pacman=make apk=make
cmake|brew=cmake apt=cmake dnf=cmake pacman=cmake apk=cmake
ninja|brew=ninja apt=ninja-build dnf=ninja-build pacman=ninja apk=ninja
bazel|brew=bazelisk
just|brew=just apt=just dnf=just pacman=just cargo=just
pkg-config|brew=pkg-config apt=pkg-config dnf=pkgconf pacman=pkgconf apk=pkgconf
autoconf|brew=autoconf apt=autoconf dnf=autoconf pacman=autoconf
gdb|brew=gdb apt=gdb dnf=gdb pacman=gdb apk=gdb
lldb|brew=llvm apt=lldb dnf=lldb pacman=lldb
protoc|brew=protobuf apt=protobuf-compiler dnf=protobuf-compiler pacman=protobuf apk=protobuf

adb|brew=android-platform-tools apt=android-sdk-platform-tools dnf=android-tools pacman=android-tools
fastlane|brew=fastlane gem=fastlane
eas|npm=eas-cli

docker|cask=docker apt=docker.io dnf=docker pacman=docker
podman|brew=podman apt=podman dnf=podman pacman=podman apk=podman
colima|brew=colima
kubectl|brew=kubectl apt=kubectl dnf=kubernetes-client pacman=kubectl
helm|brew=helm dnf=helm pacman=helm
k9s|brew=k9s pacman=k9s
minikube|brew=minikube pacman=minikube
terraform|brew=hashicorp/tap/terraform
tofu|brew=opentofu pacman=opentofu
pulumi|brew=pulumi
ansible|brew=ansible apt=ansible dnf=ansible pacman=ansible apk=ansible
vagrant|brew=hashicorp/tap/hashicorp-vagrant pacman=vagrant
aws|brew=awscli apt=awscli dnf=awscli pacman=aws-cli
cdk|npm=aws-cdk
az|brew=azure-cli pacman=azure-cli
firebase|npm=firebase-tools
wrangler|npm=wrangler
vercel|npm=vercel
netlify|npm=netlify-cli
supabase|brew=supabase/tap/supabase
flyctl|brew=flyctl
heroku|brew=heroku/brew/heroku npm=heroku
doctl|brew=doctl pacman=doctl
tailscale|cask=tailscale pacman=tailscale
ngrok|cask=ngrok
cloudflared|brew=cloudflared pacman=cloudflared

sqlite3|brew=sqlite apt=sqlite3 dnf=sqlite pacman=sqlite apk=sqlite
psql|brew=libpq apt=postgresql-client dnf=postgresql pacman=postgresql-libs
mysql|brew=mysql-client apt=default-mysql-client dnf=mysql pacman=mariadb-clients
redis-cli|brew=redis apt=redis-tools dnf=redis pacman=redis
mongosh|brew=mongosh
duckdb|brew=duckdb pacman=duckdb
dbt|pipx=dbt-core
turso|brew=tursodatabase/tap/turso

git|brew=git apt=git dnf=git pacman=git apk=git
git-lfs|brew=git-lfs apt=git-lfs dnf=git-lfs pacman=git-lfs apk=git-lfs
gh|brew=gh apt=gh dnf=gh pacman=github-cli apk=github-cli
glab|brew=glab pacman=glab
lazygit|brew=lazygit dnf=lazygit pacman=lazygit apk=lazygit
hg|brew=mercurial apt=mercurial dnf=mercurial pacman=mercurial
pre-commit|brew=pre-commit apt=pre-commit dnf=pre-commit pacman=pre-commit pipx=pre-commit

nvim|brew=neovim apt=neovim dnf=neovim pacman=neovim apk=neovim
vim|brew=vim apt=vim dnf=vim pacman=vim apk=vim
emacs|brew=emacs apt=emacs dnf=emacs pacman=emacs
code|cask=visual-studio-code
cursor|cask=cursor
zed|cask=zed
tmux|brew=tmux apt=tmux dnf=tmux pacman=tmux apk=tmux
claude|npm=@anthropic-ai/claude-code

rg|brew=ripgrep apt=ripgrep dnf=ripgrep pacman=ripgrep apk=ripgrep
fd|brew=fd apt=fd-find dnf=fd-find pacman=fd apk=fd
fzf|brew=fzf apt=fzf dnf=fzf pacman=fzf apk=fzf
bat|brew=bat apt=bat dnf=bat pacman=bat apk=bat
eza|brew=eza apt=eza dnf=eza pacman=eza
lsd|brew=lsd apt=lsd dnf=lsd pacman=lsd
zoxide|brew=zoxide apt=zoxide dnf=zoxide pacman=zoxide apk=zoxide
jq|brew=jq apt=jq dnf=jq pacman=jq apk=jq
yq|brew=yq apt=yq dnf=yq pacman=go-yq
htop|brew=htop apt=htop dnf=htop pacman=htop apk=htop
btop|brew=btop apt=btop dnf=btop pacman=btop apk=btop
tree|brew=tree apt=tree dnf=tree pacman=tree apk=tree
curl|brew=curl apt=curl dnf=curl pacman=curl apk=curl
wget|brew=wget apt=wget dnf=wget pacman=wget apk=wget
http|brew=httpie apt=httpie dnf=httpie pacman=httpie
watchman|brew=watchman
gpg|brew=gnupg apt=gnupg dnf=gnupg2 pacman=gnupg apk=gnupg
openssl|brew=openssl apt=openssl dnf=openssl pacman=openssl apk=openssl
mkcert|brew=mkcert apt=mkcert dnf=mkcert pacman=mkcert
sops|brew=sops dnf=sops pacman=sops
ffmpeg|brew=ffmpeg apt=ffmpeg dnf=ffmpeg pacman=ffmpeg apk=ffmpeg
magick|brew=imagemagick apt=imagemagick dnf=ImageMagick pacman=imagemagick apk=imagemagick
pandoc|brew=pandoc apt=pandoc dnf=pandoc pacman=pandoc
tesseract|brew=tesseract apt=tesseract-ocr dnf=tesseract pacman=tesseract

shellcheck|brew=shellcheck apt=shellcheck dnf=ShellCheck pacman=shellcheck apk=shellcheck
shfmt|brew=shfmt apt=shfmt dnf=shfmt pacman=shfmt
tsc|npm=typescript
eslint|npm=eslint
prettier|npm=prettier
ruff|brew=ruff pipx=ruff pacman=ruff
black|brew=black pipx=black pacman=python-black
mypy|brew=mypy pipx=mypy pacman=mypy
hadolint|brew=hadolint pacman=hadolint
trivy|brew=trivy pacman=trivy
semgrep|brew=semgrep pipx=semgrep
'

# Tools whose upstream install is a shell script rather than a package. These
# pipe a remote script into a shell, so they are always shown in full and
# never bundled into a silent batch.
SCRIPT_RECIPES='
rustc|curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo|curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup|curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh
uv|curl -LsSf https://astral.sh/uv/install.sh | sh
bun|curl -fsSL https://bun.sh/install | bash
deno|curl -fsSL https://deno.land/install.sh | sh
nvm|curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
sdk|curl -s https://get.sdkman.io | bash
flutter|echo "See https://docs.flutter.dev/get-started/install"
dotnet|echo "See https://dotnet.microsoft.com/download"
java|echo "Install a JDK: brew install openjdk / apt install default-jdk / sdk install java"
javac|echo "Install a JDK: brew install openjdk / apt install default-jdk / sdk install java"
gcloud|echo "See https://cloud.google.com/sdk/docs/install"
xcodebuild|echo "Install Xcode from the Mac App Store"
xcrun|echo "Run: xcode-select --install"
'

# --------------------------------------------------- manager availability ---

NEEDS_SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  NEEDS_SUDO="sudo "
fi

# Preference order. brew first where present: it is the same invocation on
# both platforms and does not need root.
manager_available() {
  case "$1" in
    brew)   command -v brew    >/dev/null 2>&1 ;;
    cask)   [ "$PLATFORM" = "mac" ] && command -v brew >/dev/null 2>&1 ;;
    apt)    command -v apt-get >/dev/null 2>&1 ;;
    dnf)    command -v dnf     >/dev/null 2>&1 ;;
    pacman) command -v pacman  >/dev/null 2>&1 ;;
    zypper) command -v zypper  >/dev/null 2>&1 ;;
    apk)    command -v apk     >/dev/null 2>&1 ;;
    npm)    command -v npm     >/dev/null 2>&1 ;;
    cargo)  command -v cargo   >/dev/null 2>&1 ;;
    pipx)   command -v pipx    >/dev/null 2>&1 ;;
    gem)    command -v gem     >/dev/null 2>&1 ;;
    go)     command -v go      >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

manager_command() {
  mgr="$1"; pkg="$2"
  case "$mgr" in
    brew)   echo "brew install $pkg" ;;
    cask)   echo "brew install --cask $pkg" ;;
    apt)    echo "${NEEDS_SUDO}env DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg" ;;
    dnf)    echo "${NEEDS_SUDO}dnf install -y $pkg" ;;
    pacman) echo "${NEEDS_SUDO}pacman -S --noconfirm $pkg" ;;
    zypper) echo "${NEEDS_SUDO}zypper install -y $pkg" ;;
    apk)    echo "${NEEDS_SUDO}apk add $pkg" ;;
    npm)    echo "npm install -g $pkg" ;;
    cargo)  echo "cargo install $pkg" ;;
    pipx)   echo "pipx install $pkg" ;;
    gem)    echo "gem install $pkg" ;;
    go)     echo "go install $pkg" ;;
  esac
}

MANAGER_ORDER="brew cask apt dnf pacman zypper apk npm cargo pipx gem go"

# Resolve the install command for a binary, or print nothing if there is no
# recipe that this machine can actually run.
resolve_install() {
  want="$1"

  spec="$(printf '%s\n' "$RECIPES" | awk -F'|' -v b="$want" '$1==b {print $2; exit}')"
  if [ -n "$spec" ]; then
    for mgr in $MANAGER_ORDER; do
      manager_available "$mgr" || continue
      for tok in $spec; do
        case "$tok" in
          "$mgr"=*) manager_command "$mgr" "${tok#*=}"; return 0 ;;
        esac
      done
    done
  fi

  script="$(printf '%s\n' "$SCRIPT_RECIPES" | awk -F'|' -v b="$want" '$1==b {sub(/^[^|]*\|/,""); print; exit}')"
  if [ -n "$script" ]; then
    printf '%s' "$script"
    return 0
  fi

  return 1
}

# ------------------------------------------------------------- the prompt ---

# Prompts read from the terminal, not stdin, so the script still behaves when
# its output is piped somewhere.
ask() {
  prompt="$1"
  REPLY=""
  # Try the controlling terminal first; fall back to stdin when there is none
  # (piped input, CI, a harness), so the script stays scriptable either way.
  if { exec 3< /dev/tty; } 2>/dev/null; then
    printf '%b' "$prompt" > /dev/tty
    IFS= read -r REPLY <&3 || REPLY=""
    exec 3<&-
  else
    printf '%b' "$prompt"
    IFS= read -r REPLY || REPLY=""
    printf '%s\n' "$REPLY"
  fi
}

# Expand "1 3 5-8" into "1 3 5 6 7 8".
expand_selection() {
  for part in $1; do
    case "$part" in
      *-*)
        lo="${part%-*}"; hi="${part#*-}"
        case "$lo$hi" in *[!0-9]*) continue ;; esac
        i="$lo"
        while [ "$i" -le "$hi" ]; do printf '%s ' "$i"; i=$((i + 1)); done
        ;;
      *)
        case "$part" in *[!0-9]*) continue ;; esac
        printf '%s ' "$part"
        ;;
    esac
  done
}

guided_install() {
  [ -z "$MISSING_RECORDS" ] && {
    printf '\n%sNothing missing — no install step needed.%s\n' "$C_GREEN" "$C_RESET"
    return 0
  }

  printf '\n%s%s%s\n' "$C_BOLD" "──────── Guided install ────────" "$C_RESET"
  printf '%sPick what to install, one category at a time. Nothing is installed\n' "$C_DIM"
  printf 'until you confirm the full plan at the end.%s\n' "$C_RESET"

  mgrs=""
  for mgr in $MANAGER_ORDER; do
    manager_available "$mgr" && mgrs="$mgrs $mgr"
  done
  printf '%sAvailable package managers:%s%s\n' "$C_DIM" "$mgrs" "$C_RESET"

  PLAN=""
  PLAN_COUNT=0

  for cat_key in $CATEGORY_ORDER; do
    wanted_category "$cat_key" || continue

    # Build the candidate list for this category.
    cand_labels=""; cand_cmds=""; n=0
    listing=""
    while IFS='|' read -r rc label bin state; do
      [ -z "${rc:-}" ] && continue
      [ "$rc" != "$cat_key" ] && continue
      cmd="$(resolve_install "$bin" 2>/dev/null || true)"
      [ -z "$cmd" ] && continue
      n=$((n + 1))
      cand_labels="$cand_labels$n|$label
"
      cand_cmds="$cand_cmds$n|$cmd
"
      tag=""
      [ "$state" = "broken" ] && tag=" ${C_YELLOW}(installed but broken)${C_RESET}"
      listing="$listing$(printf '  %2d) %-22s %s%s%s%s\n' "$n" "$label" "$C_DIM" "$cmd" "$C_RESET" "$tag")
"
    done <<CANDEOF
$(printf '%s' "$MISSING_RECORDS")
CANDEOF

    [ "$n" -eq 0 ] && continue

    printf '\n%s%s%s %s(%d available)%s\n' \
      "$C_BOLD$C_BLUE" "$(category_title "$cat_key")" "$C_RESET" "$C_DIM" "$n" "$C_RESET"
    printf '%s' "$listing"

    ask "  → numbers (e.g. 1 3 5-7), ${C_BOLD}a${C_RESET}ll, ${C_BOLD}s${C_RESET}kip, ${C_BOLD}q${C_RESET}uit: "
    sel="$REPLY"

    case "$sel" in
      q|Q|quit) printf '  %sstopping selection%s\n' "$C_DIM" "$C_RESET"; break ;;
      ""|s|S|skip|n|N) printf '  %sskipped%s\n' "$C_DIM" "$C_RESET"; continue ;;
      a|A|all) chosen="$(expand_selection "$(seq 1 "$n" | tr '\n' ' ')")" ;;
      *) chosen="$(expand_selection "$sel")" ;;
    esac

    for idx in $chosen; do
      [ "$idx" -ge 1 ] 2>/dev/null || continue
      [ "$idx" -le "$n" ] || continue
      lbl="$(printf '%s' "$cand_labels" | awk -F'|' -v i="$idx" '$1==i {print $2; exit}')"
      cmd="$(printf '%s' "$cand_cmds"   | awk -F'|' -v i="$idx" '$1==i {sub(/^[0-9]*\|/,""); print; exit}')"
      [ -z "$cmd" ] && continue
      PLAN="$PLAN$lbl|$cmd
"
      PLAN_COUNT=$((PLAN_COUNT + 1))
    done
  done

  if [ "$PLAN_COUNT" -eq 0 ]; then
    printf '\n%sNothing selected.%s\n' "$C_DIM" "$C_RESET"
    return 0
  fi

  printf '\n%sPlan — %d command(s):%s\n' "$C_BOLD" "$PLAN_COUNT" "$C_RESET"
  printf '%s' "$PLAN" | while IFS='|' read -r lbl cmd; do
    [ -z "${lbl:-}" ] && continue
    printf '  %-22s %s%s%s\n' "$lbl" "$C_DIM" "$cmd" "$C_RESET"
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n%sDry run — nothing was executed.%s\n' "$C_YELLOW" "$C_RESET"
    return 0
  fi

  if [ "$ASSUME_YES" -ne 1 ]; then
    ask "
Run these now? [y/N] "
    case "$REPLY" in
      y|Y|yes|YES) ;;
      *) printf '%sAborted — nothing was installed.%s\n' "$C_YELLOW" "$C_RESET"; return 0 ;;
    esac
  fi

  # apt needs an index refresh before the first install of a session.
  case "$PLAN" in
    *apt-get\ install*) printf '\n%s$ %sapt-get update%s\n' "$C_DIM" "$NEEDS_SUDO" "$C_RESET"
                        eval "${NEEDS_SUDO}apt-get update -qq" || true ;;
  esac

  ok_n=0; fail_n=0; failed=""
  printf '%s' "$PLAN" > /tmp/.cdt_plan.$$
  while IFS='|' read -r lbl cmd; do
    [ -z "${lbl:-}" ] && continue
    printf '\n%s==> %s%s\n%s$ %s%s\n' "$C_BOLD" "$lbl" "$C_RESET" "$C_DIM" "$cmd" "$C_RESET"
    if eval "$cmd"; then
      ok_n=$((ok_n + 1))
      printf '%s    ok%s\n' "$C_GREEN" "$C_RESET"
    else
      fail_n=$((fail_n + 1)); failed="$failed $lbl"
      printf '%s    failed%s\n' "$C_RED" "$C_RESET"
    fi
  done < /tmp/.cdt_plan.$$
  rm -f /tmp/.cdt_plan.$$

  printf '\n%sInstall summary%s  %s%d succeeded%s, %s%d failed%s\n' \
    "$C_BOLD" "$C_RESET" "$C_GREEN" "$ok_n" "$C_RESET" "$C_RED" "$fail_n" "$C_RESET"
  [ -n "$failed" ] && printf '%sFailed:%s%s\n' "$C_RED" "$C_RESET" "$failed"
  printf '%sOpen a new shell (or re-source your profile) so new tools land on PATH.%s\n' \
    "$C_DIM" "$C_RESET"
}

# --------------------------------------------------------------- run it ---

if [ "$FORMAT" = "json" ]; then
  printf '{\n'
  printf '  "platform": "%s",\n' "$PLATFORM"
  printf '  "os": "%s",\n' "$(json_escape "$(os_description)")"
  printf '  "arch": "%s",\n' "$ARCH"
  printf '  "tools": [\n'
  first=1
  for c in $CATEGORY_ORDER; do
    wanted_category "$c" || continue
    run_category "$c"
  done | while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$first" -eq 1 ]; then first=0; else printf ',\n'; fi
    printf '    %s' "$line"
  done
  printf '\n  ]\n}\n'
  exit 0
fi

printf '%sDeveloper tooling survey%s  %s%s • %s%s\n' \
  "$C_BOLD" "$C_RESET" "$C_DIM" "$(os_description)" "$ARCH" "$C_RESET"

for c in $CATEGORY_ORDER; do
  wanted_category "$c" || continue
  run_category "$c"
done

if [ -z "$ONLY_CATEGORIES" ] && [ "$SHOW" = "all" ]; then
  platform_notes
fi

printf '\n%sSummary%s  %s%d installed%s, %s%d broken%s, %s%d missing%s, %d checked\n' \
  "$C_BOLD" "$C_RESET" \
  "$C_GREEN" "$FOUND" "$C_RESET" \
  "$C_YELLOW" "$BROKEN" "$C_RESET" \
  "$C_RED" "$MISSING" "$C_RESET" \
  "$TOTAL"

if [ "$BROKEN" -gt 0 ]; then
  printf '%sBroken:%s%s\n' "$C_YELLOW" "$C_RESET" "$BROKEN_LIST"
fi

if [ "$INSTALL_MODE" -eq 1 ]; then
  guided_install
fi

if [ "$STRICT" -eq 1 ] && [ $((MISSING + BROKEN)) -gt 0 ]; then
  exit 1
fi
exit 0
