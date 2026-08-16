# shellcheck shell=bash
# Required-command detection and consented package installation.

dnsst_detect_platform() {
  DNSST_UNAME=$(uname -s)
  DNSST_OS_ID=""
  DNSST_OS_LIKE=""
  DNSST_OS_PRETTY=""
  if [ -f /etc/os-release ]; then
    # os-release is distribution metadata, not user input.
    # shellcheck disable=SC1091
    . /etc/os-release
    DNSST_OS_ID=${ID:-}
    DNSST_OS_LIKE=${ID_LIKE:-}
    DNSST_OS_PRETTY=${PRETTY_NAME:-$DNSST_OS_ID}
  fi
  case "$DNSST_UNAME" in
    Darwin)
      DNSST_PLATFORM="macOS"
      if dnsst_have_cmd sw_vers; then
        DNSST_OS_PRETTY="macOS $(sw_vers -productVersion 2>/dev/null)"
      else
        DNSST_OS_PRETTY="macOS"
      fi
      ;;
    Linux)
      DNSST_PLATFORM=${DNSST_OS_PRETTY:-Linux}
      ;;
    *)
      DNSST_PLATFORM=$DNSST_UNAME
      ;;
  esac
}

dnsst_detect_pkg_manager() {
  DNSST_PKG_MGR=""
  DNSST_PKG_INSTALL=""
  DNSST_DIG_PKG=""
  DNSST_CURL_PKG="curl"
  DNSST_UNZIP_PKG="unzip"

  case "$DNSST_UNAME" in
    Darwin)
      if dnsst_have_cmd brew; then
        DNSST_PKG_MGR="homebrew"
        DNSST_PKG_INSTALL="brew install"
        DNSST_DIG_PKG="bind"
      else
        DNSST_PKG_MGR=""
        DNSST_DIG_PKG="bind (via Homebrew) or Apple Command Line Tools"
      fi
      return 0
      ;;
  esac

  _id=$(dnsst_lc "${DNSST_OS_ID:-}")
  _like=$(dnsst_lc "${DNSST_OS_LIKE:-}")

  if dnsst_have_cmd apt-get; then
    DNSST_PKG_MGR="apt"
    DNSST_PKG_INSTALL="apt-get install -y"
    DNSST_DIG_PKG="bind9-dnsutils"
    return 0
  fi
  if dnsst_have_cmd dnf; then
    DNSST_PKG_MGR="dnf"
    DNSST_PKG_INSTALL="dnf install -y"
    DNSST_DIG_PKG="bind-utils"
    return 0
  fi
  if dnsst_have_cmd yum; then
    DNSST_PKG_MGR="yum"
    DNSST_PKG_INSTALL="yum install -y"
    DNSST_DIG_PKG="bind-utils"
    return 0
  fi
  if dnsst_have_cmd pacman; then
    DNSST_PKG_MGR="pacman"
    DNSST_PKG_INSTALL="pacman -S --noconfirm"
    DNSST_DIG_PKG="bind"
    return 0
  fi
  if dnsst_have_cmd apk; then
    DNSST_PKG_MGR="apk"
    DNSST_PKG_INSTALL="apk add"
    DNSST_DIG_PKG="bind-tools"
    return 0
  fi

  # Fallback labels when no manager is present, based on os-release.
  case "$_id $_like" in
    *debian*|*ubuntu*)
      DNSST_DIG_PKG="bind9-dnsutils"
      ;;
    *fedora*|*rhel*|*centos*)
      DNSST_DIG_PKG="bind-utils"
      ;;
    *arch*)
      DNSST_DIG_PKG="bind"
      ;;
    *alpine*)
      DNSST_DIG_PKG="bind-tools"
      ;;
    *)
      DNSST_DIG_PKG="the package that provides dig (BIND dnsutils)"
      ;;
  esac
}

dnsst_pkg_for_cmd() {
  case "$1" in
    dig) printf '%s' "$DNSST_DIG_PKG" ;;
    curl) printf '%s' "$DNSST_CURL_PKG" ;;
    unzip) printf '%s' "$DNSST_UNZIP_PKG" ;;
    *) printf '%s' "$1" ;;
  esac
}

dnsst_run_install() {
  _pkg=$1
  _cmd=$2
  if [ -z "$DNSST_PKG_MGR" ]; then
    return 1
  fi
  if [ "$DNSST_PKG_MGR" = "homebrew" ]; then
    dnsst_log "Running: brew install $_pkg"
    # shellcheck disable=SC2086
    brew install $_pkg
    return $?
  fi
  if [ "$(id -u)" -eq 0 ]; then
    dnsst_log "Running: $DNSST_PKG_INSTALL $_pkg"
    # shellcheck disable=SC2086
    $DNSST_PKG_INSTALL $_pkg
    return $?
  fi
  if dnsst_have_cmd sudo; then
    dnsst_log "Running: sudo $DNSST_PKG_INSTALL $_pkg"
    # shellcheck disable=SC2086
    sudo $DNSST_PKG_INSTALL $_pkg
    return $?
  fi
  dnsst_err "a package manager was found ($DNSST_PKG_MGR) but this user cannot install packages (not root, no sudo)."
  dnsst_err "Install '$_pkg' (provides $_cmd) as an administrator and re-run."
  return 1
}

dnsst_ask_install() {
  _cmd=$1
  _pkg=$(dnsst_pkg_for_cmd "$_cmd")
  dnsst_log ""
  dnsst_log "$_cmd was not found."
  dnsst_log "Detected platform: $DNSST_PLATFORM"
  if [ -n "$DNSST_PKG_MGR" ]; then
    dnsst_log "Package manager: $DNSST_PKG_MGR"
    dnsst_log "Required package: $_pkg"
  else
    dnsst_log "No supported package manager was found."
    dnsst_log "Required package: $_pkg"
  fi

  if [ "$DNSST_UNAME" = "Darwin" ] && [ -z "$DNSST_PKG_MGR" ]; then
    dnsst_log ""
    dnsst_log "macOS normally ships /usr/bin/dig with the Command Line Tools."
    dnsst_log "Install them with:  xcode-select --install"
    dnsst_log "Or install Homebrew yourself (this tool will not do that) and then:"
    dnsst_log "  brew install bind"
    return 1
  fi

  if [ -z "$DNSST_PKG_MGR" ]; then
    dnsst_log "Install $_pkg using your platform's package manager, then re-run."
    return 1
  fi

  if [ "$DNSST_NO_INSTALL" -eq 1 ]; then
    dnsst_log "--no-install is set; not installing $_pkg."
    return 1
  fi

  if [ "$DNSST_YES" -eq 1 ]; then
    dnsst_run_install "$_pkg" "$_cmd"
    return $?
  fi

  if [ ! -t 0 ]; then
    dnsst_log "Standard input is not a terminal. Re-run with --yes to install, or install $_pkg yourself."
    return 1
  fi

  printf 'Install it now? [y/N] ' >&2
  _ans=""
  IFS= read -r _ans || _ans=""
  case $(dnsst_lc "$_ans") in
    y|yes)
      dnsst_run_install "$_pkg" "$_cmd"
      return $?
      ;;
    *)
      dnsst_log "Not installing."
      return 1
      ;;
  esac
}

dnsst_ensure_cmd() {
  _cmd=$1
  if dnsst_have_cmd "$_cmd"; then
    return 0
  fi
  if dnsst_ask_install "$_cmd"; then
    if dnsst_have_cmd "$_cmd"; then
      return 0
    fi
    dnsst_err "$_cmd is still missing after the install attempt."
    return 1
  fi
  return 1
}

# $1 = need_download (1/0). curl+unzip only required when downloading Tranco.
dnsst_check_dependencies() {
  _need_dl=${1:-0}
  dnsst_detect_platform
  dnsst_detect_pkg_manager

  _missing=""
  _req="awk sed grep sort mktemp date tr cut wc uname mkdir mv rm cat printf head tail"
  for _c in $_req; do
    if ! dnsst_have_cmd "$_c"; then
      _missing="$_missing $_c"
    fi
  done
  if [ -n "$_missing" ]; then
    dnsst_die "required standard tools not found:$_missing"
  fi

  if ! dnsst_ensure_cmd dig; then
    dnsst_die "dig is required (BIND dnsutils). Install it and re-run."
  fi

  if [ "$_need_dl" -eq 1 ]; then
    if ! dnsst_ensure_cmd curl; then
      dnsst_die "curl is required to download the Tranco domain list (or pass --domain-file)."
    fi
    if ! dnsst_ensure_cmd unzip; then
      dnsst_die "unzip is required to extract the Tranco zip (or pass --domain-file)."
    fi
  fi
}
