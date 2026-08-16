# shellcheck shell=bash
# Parse the resolver TSV. Never source the file as Bash.

# Parallel arrays (Bash 3.2 has no associative arrays):
#   DNSST_R_PROVIDER[i] DNSST_R_IP[i] DNSST_R_SERVICE[i]
#   DNSST_R_FILTER[i] DNSST_R_NOTES[i] DNSST_R_SOURCE[i] DNSST_R_ENABLED[i]

dnsst_resolver_file_default() {
  printf '%s' "$DNSST_ROOT/config/resolvers.tsv"
}

dnsst_parse_resolvers() {
  local _file _include_disabled _lineno _usable _line _trimmed _nf
  local _en _prov _ip _svc _filt _notes _src _enb
  _file=$1
  _include_disabled=${2:-0}
  if [ ! -f "$_file" ]; then
    dnsst_die "resolver file not found: $_file"
  fi
  if [ ! -r "$_file" ]; then
    dnsst_die "resolver file is not readable: $_file"
  fi

  DNSST_R_PROVIDER=()
  DNSST_R_IP=()
  DNSST_R_SERVICE=()
  DNSST_R_FILTER=()
  DNSST_R_NOTES=()
  DNSST_R_SOURCE=()
  DNSST_R_ENABLED=()
  DNSST_R_COUNT=0

  _lineno=0
  _usable=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _lineno=$((_lineno + 1))
    _line=$(printf '%s' "$_line" | dnsst_strip_cr)
    case "$_line" in
      ''|\#*) continue ;;
    esac
    # Allow a leading comment after whitespace.
    _trimmed=$(printf '%s' "$_line" | dnsst_trim)
    case "$_trimmed" in
      ''|\#*) continue ;;
    esac

    _nf=$(printf '%s' "$_line" | awk -F '\t' '{ print NF }')
    if [ "$_nf" -lt 6 ]; then
      dnsst_die "$_file:$_lineno: expected at least 6 tab-separated fields (enabled, provider, ip, service_type, filtering, notes[, source]), found $_nf"
    fi

    _en=$(printf '%s' "$_line" | awk -F '\t' '{ print $1 }' | dnsst_trim)
    _prov=$(printf '%s' "$_line" | awk -F '\t' '{ print $2 }' | dnsst_trim)
    _ip=$(printf '%s' "$_line" | awk -F '\t' '{ print $3 }' | dnsst_trim)
    _svc=$(printf '%s' "$_line" | awk -F '\t' '{ print $4 }' | dnsst_trim)
    _filt=$(printf '%s' "$_line" | awk -F '\t' '{ print $5 }' | dnsst_trim)
    _notes=$(printf '%s' "$_line" | awk -F '\t' '{ print $6 }' | dnsst_trim)
    _src=$(printf '%s' "$_line" | awk -F '\t' '{ print $7 }' | dnsst_trim)

    _enb=$(dnsst_bool_word "$_en") || \
      dnsst_die "$_file:$_lineno: invalid enabled flag '$_en' (use 1/0, yes/no, true/false)"

    [ -n "$_prov" ] || dnsst_die "$_file:$_lineno: provider is empty"
    [ -n "$_ip" ] || dnsst_die "$_file:$_lineno: resolver IP is empty"
    dnsst_is_ip "$_ip" || \
      dnsst_die "$_file:$_lineno: '$_ip' is not a valid IPv4 or IPv6 address (hostnames are not accepted)"

    # Hostnames must not sneak through the IPv6 check (they lack ':').
    case "$_ip" in
      *[!0-9A-Fa-f:.]*)
        dnsst_die "$_file:$_lineno: '$_ip' is not a valid resolver IP"
        ;;
    esac

    DNSST_R_PROVIDER[DNSST_R_COUNT]=$_prov
    DNSST_R_IP[DNSST_R_COUNT]=$_ip
    DNSST_R_SERVICE[DNSST_R_COUNT]=$_svc
    DNSST_R_FILTER[DNSST_R_COUNT]=$_filt
    DNSST_R_NOTES[DNSST_R_COUNT]=$_notes
    DNSST_R_SOURCE[DNSST_R_COUNT]=$_src
    DNSST_R_ENABLED[DNSST_R_COUNT]=$_enb
    if [ "$_enb" = "1" ] || [ "$_include_disabled" = "1" ]; then
      _usable=$((_usable + 1))
    fi
    DNSST_R_COUNT=$((DNSST_R_COUNT + 1))
  done < "$_file"

  if [ "$DNSST_R_COUNT" -eq 0 ]; then
    dnsst_die "$_file: no resolver rows found"
  fi
  if [ "$_usable" -eq 0 ]; then
    dnsst_die "$_file: no enabled resolvers (edit the file or pass --include-disabled)"
  fi
}

# Build the list of resolver indexes that will actually be queried.
dnsst_select_resolvers() {
  DNSST_SEL=()
  DNSST_SEL_COUNT=0
  _i=0
  while [ "$_i" -lt "$DNSST_R_COUNT" ]; do
    if [ "${DNSST_R_ENABLED[_i]}" = "1" ] || [ "${DNSST_INCLUDE_DISABLED:-0}" = "1" ]; then
      DNSST_SEL[DNSST_SEL_COUNT]=$_i
      DNSST_SEL_COUNT=$((DNSST_SEL_COUNT + 1))
    fi
    _i=$((_i + 1))
  done
}

dnsst_print_resolvers() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "enabled" "provider" "ip" "service" "filtering" "notes"
  _i=0
  while [ "$_i" -lt "$DNSST_R_COUNT" ]; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${DNSST_R_ENABLED[_i]}" \
      "${DNSST_R_PROVIDER[_i]}" \
      "${DNSST_R_IP[_i]}" \
      "${DNSST_R_SERVICE[_i]}" \
      "${DNSST_R_FILTER[_i]}" \
      "${DNSST_R_NOTES[_i]}"
    _i=$((_i + 1))
  done
}
