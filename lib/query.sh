# shellcheck shell=bash
# Invoke dig against a resolver IP and classify the response.
# Measurement is the Query time reported by dig, never wall-clock.

# Run one query. Prints a single TSV line:
#   rcode  outcome  success  query_time_ms  answer_count  error_type
#
# outcome: success | timeout | servfail | refused | other_rcode | command_failure
# success: 1 only when a DNS response of NOERROR or NXDOMAIN includes Query time
dnsst_run_dig() {
  local _ip _domain _qtype _timeout _home _out _rc
  _ip=$1
  _domain=$2
  _qtype=${3:-A}
  _timeout=${4:-2}

  # Isolate ~/.digrc. macOS BIND 9.10.6 has no portable -r flag.
  _home=${DNSST_WORKDIR:-${TMPDIR:-/tmp}}
  _out=""
  _rc=0
  _out=$(
    HOME="$_home" \
    dig +"time=${_timeout}" +tries=1 +retry=0 \
      +nosearch +ignore +nocmd +noquestion \
      +noauthority +noadditional \
      +comments +stats +answer \
      @"$_ip" "$_domain" "$_qtype" 2>&1
  ) || _rc=$?

  dnsst_classify_dig "$_out" "$_rc"
}

# Classify already-captured dig output (also used by tests).
dnsst_classify_dig() {
  local _out _rc _rcode _qtime _ans _outcome _success _err _lc _is_timeout
  _out=$1
  _rc=${2:-0}

  _rcode=""
  _qtime=""
  _ans=""
  _outcome="command_failure"
  _success=0
  _err="command_failure"

  # Portable extraction (BSD awk / macOS sed / GNU sed).
  _rcode=$(printf '%s\n' "$_out" | sed -n 's/.*status:[[:space:]]*\([A-Za-z0-9][A-Za-z0-9]*\).*/\1/p' | head -1)
  _qtime=$(printf '%s\n' "$_out" | sed -n 's/.*Query time:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*msec.*/\1/p' | head -1)
  _ans=$(printf '%s\n' "$_out" | sed -n 's/.*ANSWER:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)

  _rcode=$(printf '%s' "$_rcode" | tr '[:lower:]' '[:upper:]')

  _lc=$(printf '%s' "$_out" | tr '[:upper:]' '[:lower:]')
  _is_timeout=0
  case "$_lc" in
    *'connection timed out'*|*'timed out'*|*'no servers could be reached'*)
      _is_timeout=1
      ;;
  esac

  if [ "$_is_timeout" -eq 1 ] && [ -z "$_rcode" ]; then
    _outcome="timeout"
    _err="timeout"
    _rcode="TIMEOUT"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_rcode" "$_outcome" "$_success" "$_qtime" "${_ans:-}" "$_err"
    return 0
  fi

  if [ -z "$_rcode" ]; then
    case "$_lc" in
      *'communications error'*|*'connection refused'*|*'network is unreachable'*|*'host unreachable'*|*'connection reset'*)
        _outcome="timeout"
        _err="timeout"
        _rcode="TIMEOUT"
        ;;
      *)
        _outcome="command_failure"
        _err="command_failure"
        _rcode="COMMAND_FAILURE"
        ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_rcode" "$_outcome" "$_success" "$_qtime" "${_ans:-}" "$_err"
    return 0
  fi

  case "$_rcode" in
    NOERROR)
      if [ -n "$_qtime" ]; then
        _outcome="success"
        _success=1
        _err=""
      else
        _outcome="other_rcode"
        _err="missing_query_time"
      fi
      ;;
    NXDOMAIN)
      if [ -n "$_qtime" ]; then
        _outcome="success"
        _success=1
        _err="nxdomain"
      else
        _outcome="other_rcode"
        _err="missing_query_time"
      fi
      ;;
    SERVFAIL)
      _outcome="servfail"
      _err="servfail"
      ;;
    REFUSED)
      _outcome="refused"
      _err="refused"
      ;;
    *)
      _outcome="other_rcode"
      _err="rcode_$(dnsst_lc "$_rcode")"
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$_rcode" "$_outcome" "$_success" "$_qtime" "${_ans:-}" "$_err"
}

# Worker used by sequential and parallel modes. Writes one result file.
# Args: outfile domain resolver_index elapsed_start_epoch
dnsst_query_worker() {
  local _outfile _domain _ri _start _ip _prov _filt _now _rel _line
  local _rcode _outcome _success _qtime _ans _err
  _outfile=$1
  _domain=$2
  _ri=$3
  _start=$4
  _ip=${DNSST_R_IP[_ri]}
  _prov=${DNSST_R_PROVIDER[_ri]}
  _filt=${DNSST_R_FILTER[_ri]}
  _now=$(dnsst_now_epoch)
  _rel=$((_now - _start))

  _line=$(dnsst_run_dig "$_ip" "$_domain" "$DNSST_QUERY_TYPE" "$DNSST_QUERY_TIMEOUT")
  # rcode outcome success qtime answers err
  _rcode=$(printf '%s' "$_line" | awk -F '\t' '{ print $1 }')
  _outcome=$(printf '%s' "$_line" | awk -F '\t' '{ print $2 }')
  _success=$(printf '%s' "$_line" | awk -F '\t' '{ print $3 }')
  _qtime=$(printf '%s' "$_line" | awk -F '\t' '{ print $4 }')
  _ans=$(printf '%s' "$_line" | awk -F '\t' '{ print $5 }')
  _err=$(printf '%s' "$_line" | awk -F '\t' '{ print $6 }')

  {
    printf '%s\t' "$_now"
    printf '%s\t' "$_rel"
    printf '%s\t' "$_domain"
    printf '%s\t' "$_prov"
    printf '%s\t' "$_ip"
    printf '%s\t' "$DNSST_QUERY_TYPE"
    printf '%s\t' "$_rcode"
    printf '%s\t' "$_outcome"
    printf '%s\t' "$_success"
    printf '%s\t' "$_qtime"
    printf '%s\t' "$_ans"
    printf '%s\t' "$_err"
    printf '%s\n' "$_filt"
  } > "$_outfile"
}
