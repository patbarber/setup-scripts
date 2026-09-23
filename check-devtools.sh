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

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; }

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
      [ "$SHOW" = "installed" ] && continue
      mark="${C_YELLOW}!${C_RESET}"
      version="on PATH but not runnable — ${version}"
    else
      MISSING=$((MISSING + 1))
      MISSING_LIST="$MISSING_LIST $label"
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

if [ "$STRICT" -eq 1 ] && [ $((MISSING + BROKEN)) -gt 0 ]; then
  exit 1
fi
exit 0
