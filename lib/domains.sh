# shellcheck shell=bash
# Tranco download, cache, and domain-list parsing.

DNSST_TRANCO_URL="https://tranco-list.eu/top-1m.csv.zip"

dnsst_cache_dir() {
  if [ -n "${XDG_CACHE_HOME:-}" ]; then
    printf '%s' "$XDG_CACHE_HOME/dns-speedtest"
  else
    printf '%s' "$HOME/.cache/dns-speedtest"
  fi
}

dnsst_cache_file() {
  printf '%s' "$(dnsst_cache_dir)/tranco-top-1m.csv"
}

dnsst_cache_meta() {
  printf '%s' "$(dnsst_cache_dir)/tranco-top-1m.meta"
}

# A cached Tranco CSV is valid if it has a reasonable number of rank,domain rows.
dnsst_cache_is_valid() {
  _f=$1
  [ -f "$_f" ] || return 1
  [ -s "$_f" ] || return 1
  _n=$(awk -F ',' '
    BEGIN { n=0 }
    {
      gsub(/\r/, "")
      if ($0 ~ /^[0-9]+,[A-Za-z0-9._-]+$/) n++
      if (n >= 20) { print n; exit }
    }
    END { if (n < 20) print n }
  ' "$_f")
  [ "$_n" -ge 20 ]
}

dnsst_download_tranco() {
  _dest=$1
  _dir=$(dirname "$_dest")
  dnsst_mkdir_p "$_dir"
  _tmpd=$(mktemp -d "${TMPDIR:-/tmp}/dnsst-dl.XXXXXX") || return 1
  _zip="$_tmpd/top-1m.csv.zip"
  _csv="$_tmpd/top-1m.csv"

  dnsst_info "Downloading Tranco top-1M from $DNSST_TRANCO_URL ..."
  if ! curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 20 \
      --max-time 180 \
      -A "dns-speedtest/$DNSST_VERSION" \
      -o "$_zip" "$DNSST_TRANCO_URL"; then
    rm -rf "$_tmpd"
    return 1
  fi
  if [ ! -s "$_zip" ]; then
    rm -rf "$_tmpd"
    return 1
  fi
  # First entry in the zip should be the CSV.
  if ! unzip -p "$_zip" > "$_csv" 2>/dev/null; then
    rm -rf "$_tmpd"
    return 1
  fi
  if ! dnsst_cache_is_valid "$_csv"; then
    rm -rf "$_tmpd"
    return 1
  fi
  if ! mv "$_csv" "$_dest"; then
    rm -rf "$_tmpd"
    return 1
  fi
  {
    printf 'url=%s\n' "$DNSST_TRANCO_URL"
    printf 'downloaded=%s\n' "$(dnsst_iso8601)"
  } > "$(dnsst_cache_meta)"
  rm -rf "$_tmpd"
  return 0
}

# Populate DNSST_DOMAINS[] / DNSST_DOMAIN_COUNT_ACTUAL from a file of names.
# $1 file  $2 max_count (0 = all)
dnsst_load_domain_file() {
  local _file _max _lineno _skipped _line _maybe
  _file=$1
  _max=${2:-0}
  if [ ! -f "$_file" ]; then
    dnsst_die "domain file not found: $_file"
  fi
  DNSST_DOMAINS=()
  DNSST_DOMAIN_N=0
  _lineno=0
  _skipped=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _lineno=$((_lineno + 1))
    _line=$(printf '%s' "$_line" | dnsst_strip_cr)
    _line=$(printf '%s' "$_line" | dnsst_trim)
    case "$_line" in
      ''|\#*) continue ;;
    esac
    # Tranco / Alexa-style "rank,domain" — take the last comma field if the
    # first field is entirely digits.
    case "$_line" in
      [0-9]*,*)
        _maybe=$(printf '%s' "$_line" | awk -F ',' '{ print $2 }' | dnsst_trim)
        [ -n "$_maybe" ] && _line=$_maybe
        ;;
    esac
    if ! dnsst_is_domain "$_line"; then
      dnsst_warn "$_file:$_lineno: ignoring invalid domain '$_line'"
      _skipped=$((_skipped + 1))
      if [ "$_skipped" -ge 50 ]; then
        dnsst_die "$_file: too many invalid domain lines; aborting"
      fi
      continue
    fi
    DNSST_DOMAINS[DNSST_DOMAIN_N]=$_line
    DNSST_DOMAIN_N=$((DNSST_DOMAIN_N + 1))
    if [ "$_max" -gt 0 ] && [ "$DNSST_DOMAIN_N" -ge "$_max" ]; then
      break
    fi
  done < "$_file"
  if [ "$DNSST_DOMAIN_N" -eq 0 ]; then
    dnsst_die "$_file: no valid domains found"
  fi
}

dnsst_prepare_domains() {
  DNSST_DOMAIN_SOURCE="tranco"
  DNSST_DOMAIN_CACHE_USED=0
  DNSST_DOMAIN_CACHE_PATH=""
  DNSST_DOMAIN_DOWNLOAD_OK=0

  _max=0
  if [ "${DNSST_DOMAIN_COUNT_ALL:-0}" -eq 0 ]; then
    _max=$DNSST_DOMAIN_COUNT
  fi

  if [ -n "${DNSST_DOMAIN_FILE:-}" ]; then
    DNSST_DOMAIN_SOURCE="file:$DNSST_DOMAIN_FILE"
    dnsst_load_domain_file "$DNSST_DOMAIN_FILE" "$_max"
    return 0
  fi

  _cache=$(dnsst_cache_file)
  DNSST_DOMAIN_CACHE_PATH=$_cache

  if [ "${DNSST_REFRESH_DOMAINS:-0}" -eq 1 ] || ! dnsst_cache_is_valid "$_cache"; then
    if dnsst_download_tranco "$_cache"; then
      DNSST_DOMAIN_DOWNLOAD_OK=1
    else
      if dnsst_cache_is_valid "$_cache"; then
        dnsst_warn "failed to download a fresh Tranco list; using cached copy at $_cache"
        DNSST_DOMAIN_CACHE_USED=1
      else
        dnsst_err "failed to download the Tranco list and no valid cache exists at $_cache"
        dnsst_err "Provide a local list with --domain-file FILE (one domain per line)."
        dnsst_err "Source: $DNSST_TRANCO_URL"
        exit 1
      fi
    fi
  else
    DNSST_DOMAIN_CACHE_USED=1
    dnsst_info "Using cached Tranco list: $_cache"
  fi

  dnsst_load_domain_file "$_cache" "$_max"
}
