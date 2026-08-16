# shellcheck shell=bash
# Shared helpers. Sourced; never executed as a program.
# Compatible with Bash 3.2 (macOS /bin/bash).

DNSST_VERSION="1.0.0"
DNSST_AUTHOR="Emre Ozudogru"

dnsst_log() {
  printf '%s\n' "$*" >&2
}

dnsst_info() {
  [ "${DNSST_QUIET:-0}" = "1" ] && return 0
  printf '%s\n' "$*" >&2
}

dnsst_warn() {
  printf 'warning: %s\n' "$*" >&2
}

dnsst_err() {
  printf 'error: %s\n' "$*" >&2
}

dnsst_die() {
  dnsst_err "$*"
  exit 1
}

dnsst_now_epoch() {
  date +%s
}

dnsst_stamp() {
  date +%Y%m%d-%H%M%S
}

dnsst_iso8601() {
  # Portable enough: local time with numeric offset when the OS supports %z.
  date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

dnsst_trim() {
  # stdin -> stdout
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

dnsst_strip_cr() {
  tr -d '\r'
}

dnsst_lc() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

dnsst_is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Parse a duration used by --duration and --stats-interval.
# Accepts: 30, 30s, 5m, 1h, 90s. Units are s/m/h (case-insensitive).
# Prints seconds on stdout. Returns 1 on error.
dnsst_parse_duration() {
  local _raw _norm _num _unit
  _raw=$1
  [ -n "$_raw" ] || return 1
  _norm=$(printf '%s' "$_raw" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  case "$_norm" in
    *[!0-9smh]*) return 1 ;;
  esac
  # Bare number = seconds.
  case "$_norm" in
    [0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9][0-9]|[0-9]*)
      if dnsst_is_uint "$_norm"; then
        [ "$_norm" -gt 0 ] || return 1
        printf '%s\n' "$_norm"
        return 0
      fi
      ;;
  esac
  _num=$(printf '%s' "$_norm" | sed 's/[smh]$//')
  _unit=$(printf '%s' "$_norm" | sed 's/.*\([smh]\)$/\1/')
  dnsst_is_uint "$_num" || return 1
  [ "$_num" -gt 0 ] || return 1
  case "$_unit" in
    s) printf '%s\n' "$_num" ;;
    m) printf '%s\n' $((_num * 60)) ;;
    h) printf '%s\n' $((_num * 3600)) ;;
    *) return 1 ;;
  esac
}

dnsst_format_duration() {
  _s=$1
  dnsst_is_uint "$_s" || { printf '%s' "$_s"; return 0; }
  _h=$((_s / 3600))
  _m=$(((_s % 3600) / 60))
  _r=$((_s % 60))
  if [ "$_h" -gt 0 ]; then
    printf '%d:%02d:%02d' "$_h" "$_m" "$_r"
  else
    printf '%d:%02d' "$_m" "$_r"
  fi
}

dnsst_is_ipv4() {
  _ip=$1
  case "$_ip" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  _oldifs=$IFS
  IFS=.
  # shellcheck disable=SC2086
  set -- $_ip
  IFS=$_oldifs
  [ $# -eq 4 ] || return 1
  for _o in "$1" "$2" "$3" "$4"; do
    dnsst_is_uint "$_o" || return 1
    [ "$_o" -le 255 ] || return 1
    # Disallow empty via uint check; leading zeros are tolerated (008).
  done
  return 0
}

# Permissive IPv6 recognizer. Accepts compressed forms and v4-mapped.
# Rejects empty, hostnames, and strings with illegal characters.
dnsst_is_ipv6() {
  _ip=$1
  case "$_ip" in
    *:*) ;;
    *) return 1 ;;
  esac
  case "$_ip" in
    *[!0-9A-Fa-f:.]*) return 1 ;;
  esac
  # At most one '::'
  _rest=${_ip#*::}
  case "$_rest" in
    *"::"*) return 1 ;;
  esac
  [ "${#_ip}" -ge 2 ] && [ "${#_ip}" -le 45 ] || return 1
  return 0
}

dnsst_is_ip() {
  dnsst_is_ipv4 "$1" || dnsst_is_ipv6 "$1"
}

# Domain-ish names safe to pass as a dig argument.
# Allows letters, digits, hyphen, dot, underscore (some CDNs), and punycode.
dnsst_is_domain() {
  _d=$1
  [ -n "$_d" ] || return 1
  [ "${#_d}" -le 253 ] || return 1
  case "$_d" in
    .*|*.) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
    *..*) return 1 ;;
  esac
  return 0
}

dnsst_csv_escape() {
  # RFC 4180: quote if the field contains comma, quote, CR, or LF.
  _s=$1
  case "$_s" in
    *[\",$'\n'$'\r']*)
      _s=$(printf '%s' "$_s" | awk '{
        gsub(/"/, "\"\"")
        printf "\"%s\"", $0
      }')
      printf '%s' "$_s"
      ;;
    *)
      printf '%s' "$_s"
      ;;
  esac
}

dnsst_json_escape() {
  # Escape a string for JSON. No jq.
  printf '%s' "$1" | awk '
    BEGIN { ORS="" }
    {
      s = $0
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      gsub(/\t/, "\\t", s)
      gsub(/\r/, "\\r", s)
      # awk may not see embedded newlines if RS is default; handle per line
      printf "%s", s
    }
    END { }
  '
  # If the original contained newlines, awk split them. Re-join as \n
  # by processing with a more careful loop when needed. For our fields
  # (IPs, domains, RCODEs) newlines are rejected upstream.
}

dnsst_json_str() {
  printf '"'
  dnsst_json_escape "$1"
  printf '"'
}

dnsst_json_num_or_null() {
  if [ -n "$1" ]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

dnsst_have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

dnsst_os_name() {
  uname -s
}

dnsst_bash_version() {
  printf '%s' "${BASH_VERSION:-unknown}"
}

# Resolve the directory containing the main script (one symlink hop).
dnsst_script_dir() {
  _src=${1:-${BASH_SOURCE[0]}}
  _dir=$(cd "$(dirname "$_src")" && pwd) || return 1
  if [ -L "$_src" ]; then
    _link=$(readlink "$_src" 2>/dev/null)
    case "$_link" in
      /*) _dir=$(cd "$(dirname "$_link")" && pwd) || return 1 ;;
      *) _dir=$(cd "$_dir/$(dirname "$_link")" && pwd) || return 1 ;;
    esac
  fi
  printf '%s' "$_dir"
}

dnsst_mkdir_p() {
  mkdir -p "$1" || dnsst_die "cannot create directory: $1"
}

dnsst_is_tty() {
  [ -t 1 ]
}

dnsst_term_cols() {
  _c=${COLUMNS:-}
  if [ -z "$_c" ] && dnsst_have_cmd tput; then
    _c=$(tput cols 2>/dev/null || true)
  fi
  if dnsst_is_uint "${_c:-}"; then
    printf '%s\n' "$_c"
  else
    printf '80\n'
  fi
}

dnsst_bool_word() {
  case $(dnsst_lc "$1") in
    1|y|yes|true|on|enabled) printf '1' ;;
    0|n|no|false|off|disabled) printf '0' ;;
    *) return 1 ;;
  esac
}
