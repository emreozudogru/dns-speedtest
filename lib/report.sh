# shellcheck shell=bash
# Live progress, final table, and machine-readable result files.

dnsst_results_init() {
  dnsst_mkdir_p "$DNSST_OUTDIR"
  DNSST_QUERIES_CSV="$DNSST_OUTDIR/queries.csv"
  DNSST_SUMMARY_CSV="$DNSST_OUTDIR/summary.csv"
  DNSST_SUMMARY_JSON="$DNSST_OUTDIR/summary.json"
  DNSST_META_TXT="$DNSST_OUTDIR/metadata.txt"
  DNSST_META_JSON="$DNSST_OUTDIR/metadata.json"

  {
    printf '%s\n' "timestamp,elapsed_s,domain,provider,resolver_ip,query_type,dns_status,outcome,success,query_time_ms,answer_count,error_type,filtering"
  } > "$DNSST_QUERIES_CSV"

  DNSST_QUERY_TOTAL=0
  DNSST_DOMAINS_DONE=0
  DNSST_CURRENT_DOMAIN=""
  DNSST_LAST_STATS_AT=0
  DNSST_TTY_LINES=0
  DNSST_USE_TTY=0
  if [ "${DNSST_QUIET:-0}" -eq 0 ] && dnsst_is_tty; then
    DNSST_USE_TTY=1
  fi
}

# Append one worker result file to queries.csv and update stats.
dnsst_ingest_result() {
  local _rf _ts _el _dom _prov _ip _qt _st _outc _ok _qtms _ans _err _filt _ri
  _rf=$1
  [ -f "$_rf" ] || return 0
  _ts=$(awk -F '\t' '{ print $1 }' "$_rf")
  _el=$(awk -F '\t' '{ print $2 }' "$_rf")
  _dom=$(awk -F '\t' '{ print $3 }' "$_rf")
  _prov=$(awk -F '\t' '{ print $4 }' "$_rf")
  _ip=$(awk -F '\t' '{ print $5 }' "$_rf")
  _qt=$(awk -F '\t' '{ print $6 }' "$_rf")
  _st=$(awk -F '\t' '{ print $7 }' "$_rf")
  _outc=$(awk -F '\t' '{ print $8 }' "$_rf")
  _ok=$(awk -F '\t' '{ print $9 }' "$_rf")
  _qtms=$(awk -F '\t' '{ print $10 }' "$_rf")
  _ans=$(awk -F '\t' '{ print $11 }' "$_rf")
  _err=$(awk -F '\t' '{ print $12 }' "$_rf")
  _filt=$(awk -F '\t' '{ print $13 }' "$_rf")
  _ri=$2

  {
    dnsst_csv_escape "$_ts"; printf ','
    dnsst_csv_escape "$_el"; printf ','
    dnsst_csv_escape "$_dom"; printf ','
    dnsst_csv_escape "$_prov"; printf ','
    dnsst_csv_escape "$_ip"; printf ','
    dnsst_csv_escape "$_qt"; printf ','
    dnsst_csv_escape "$_st"; printf ','
    dnsst_csv_escape "$_outc"; printf ','
    dnsst_csv_escape "$_ok"; printf ','
    dnsst_csv_escape "$_qtms"; printf ','
    dnsst_csv_escape "$_ans"; printf ','
    dnsst_csv_escape "$_err"; printf ','
    dnsst_csv_escape "$_filt"; printf '\n'
  } >> "$DNSST_QUERIES_CSV"

  dnsst_stats_record "$_ri" "$_ok" "$_qtms" "$_err"
  DNSST_QUERY_TOTAL=$((DNSST_QUERY_TOTAL + 1))

  if [ -n "${DNSST_ORDER_LOG:-}" ]; then
    printf '%s %s\n' "$_dom" "$_ip" >> "$DNSST_ORDER_LOG"
  fi
}

dnsst_maybe_live_stats() {
  local _now _delta
  [ "${DNSST_QUIET:-0}" -eq 0 ] || return 0
  _now=$(dnsst_now_epoch)
  if [ "$DNSST_LAST_STATS_AT" -ne 0 ]; then
    _delta=$((_now - DNSST_LAST_STATS_AT))
    [ "$_delta" -ge "$DNSST_STATS_INTERVAL_SECS" ] || return 0
  fi
  DNSST_LAST_STATS_AT=$_now
  dnsst_render_live
}

dnsst_render_live() {
  local _now _elapsed _ebudget _eline _block _k _ri _ip _prov _att _ok _to
  local _last _rate _st _mean _med _p95 _u
  _now=$(dnsst_now_epoch)
  _elapsed=$((_now - DNSST_START_EPOCH))
  _ebudget="-"
  if [ "${DNSST_DURATION_SECS:-0}" -gt 0 ]; then
    _ebudget=$(dnsst_format_duration "$DNSST_DURATION_SECS")
  fi
  _eline=$(dnsst_format_duration "$_elapsed")

  _block=""
  _block="${_block}dns-speedtest  elapsed ${_eline}"
  if [ "$_ebudget" != "-" ]; then
    _block="${_block} / ${_ebudget}"
  fi
  _block="${_block}  domains ${DNSST_DOMAINS_DONE}/${DNSST_DOMAIN_N}  queries ${DNSST_QUERY_TOTAL}"$'\n'
  _block="${_block}current: ${DNSST_CURRENT_DOMAIN:-}"$'\n'

  _k=0
  while [ "$_k" -lt "$DNSST_SEL_COUNT" ]; do
    _ri=${DNSST_SEL[_k]}
    _ip=${DNSST_R_IP[_ri]}
    _prov=${DNSST_R_PROVIDER[_ri]}
    _att=$(dnsst_stats_get "$_ri" attempted)
    _ok=$(dnsst_stats_get "$_ri" success)
    _to=$(dnsst_stats_get "$_ri" timeout)
    _last=$(cat "$DNSST_WORKDIR/s/$_ri.last" 2>/dev/null || true)
    _rate="-"
    [ "$_att" -gt 0 ] && _rate=$(dnsst_pct "$_ok" "$_att")"%"
    _st=$(dnsst_times_stats "$DNSST_WORKDIR/s/$_ri.times")
    _mean=$(printf '%s' "$_st" | awk '{ print $4 }')
    _med=$(printf '%s' "$_st" | awk '{ print $5 }')
    _p95=$(printf '%s' "$_st" | awk '{ print $6 }')
    if [ -z "$_mean" ]; then
      _mean="-"
    fi
    [ -n "$_med" ] || _med="-"
    [ -n "$_p95" ] || _p95="-"
    [ -n "$_last" ] || _last="-"
    _block="${_block}$(printf '%-12.12s %-22.22s n=%-5s ok=%-7s avg=%-7s med=%-7s p95=%-6s last=%-5s to=%s' \
      "$_prov" "$_ip" "$_att" "$_rate" "$_mean" "$_med" "$_p95" "$_last" "$_to")"$'\n'
    _k=$((_k + 1))
  done

  if [ "$DNSST_USE_TTY" -eq 1 ]; then
    if [ "$DNSST_TTY_LINES" -gt 0 ]; then
      # Move cursor up and clear each line we previously wrote.
      _u=0
      while [ "$_u" -lt "$DNSST_TTY_LINES" ]; do
        printf '\033[1A\033[2K' >&2
        _u=$((_u + 1))
      done
    fi
    printf '%s' "$_block" >&2
    DNSST_TTY_LINES=$(printf '%s' "$_block" | awk 'END { print NR }')
  else
    printf 'elapsed %s' "$_eline" >&2
    if [ "$_ebudget" != "-" ]; then
      printf ' / %s' "$_ebudget" >&2
    fi
    printf '  domains %s/%s  queries %s  current %s\n' \
      "$DNSST_DOMAINS_DONE" "$DNSST_DOMAIN_N" "$DNSST_QUERY_TOTAL" \
      "${DNSST_CURRENT_DOMAIN:-}" >&2
  fi
}

dnsst_fmt_ms() {
  if [ -z "$1" ]; then
    printf '-'
    return 0
  fi
  if [ "$1" = "0" ] && [ ! -s "$2" ]; then
    printf '-'
    return 0
  fi
  case "$1" in
    *.0) printf '%sms' "${1%.0}" ;;
    *.*) printf '%sms' "$1" ;;
    *) printf '%sms' "$1" ;;
  esac
}

dnsst_print_final_table() {
  local _hdr _i _w _pos _k _ri _prov _ip _filt _att _ok _to _rate _st
  local _n _min _max _mean _med _p95 _p99 _tf _mean_s _med_s _p95_s _p99_s _mm _notes
  dnsst_rank_resolvers
  printf '\n'
  printf 'DNS resolver ranking  (median of successful query times; UNRELIABLE if success < %s%% or < %s samples)\n' \
    "$DNSST_RELIABLE_RATE" "$DNSST_RELIABLE_MIN_OK"
  printf '\n'
  _hdr=$(printf '%-4s %-14s %-22s %8s %8s %8s %8s %8s %8s %8s %6s  %s' \
    "#" "Provider" "Resolver" "Queries" "Success" "Avg" "Median" "P95" "P99" "Min/Max" "TO" "Notes")
  printf '%s\n' "$_hdr"
  _i=0
  _w=${#_hdr}
  while [ "$_i" -lt "$_w" ]; do
    printf '-'
    _i=$((_i + 1))
  done
  printf '\n'

  _pos=1
  _k=0
  while [ "$_k" -lt "$DNSST_RANK_COUNT" ]; do
    _ri=${DNSST_RANK[_k]}
    _prov=${DNSST_R_PROVIDER[_ri]}
    _ip=${DNSST_R_IP[_ri]}
    _filt=${DNSST_R_FILTER[_ri]}
    _att=$(dnsst_stats_get "$_ri" attempted)
    _ok=$(dnsst_stats_get "$_ri" success)
    _to=$(dnsst_stats_get "$_ri" timeout)
    _rate="-"
    [ "$_att" -gt 0 ] && _rate=$(dnsst_pct "$_ok" "$_att")"%"
    _st=$(dnsst_times_stats "$DNSST_WORKDIR/s/$_ri.times")
    _n=$(printf '%s' "$_st" | awk '{ print $1 }')
    _min=$(printf '%s' "$_st" | awk '{ print $2 }')
    _max=$(printf '%s' "$_st" | awk '{ print $3 }')
    _mean=$(printf '%s' "$_st" | awk '{ print $4 }')
    _med=$(printf '%s' "$_st" | awk '{ print $5 }')
    _p95=$(printf '%s' "$_st" | awk '{ print $6 }')
    _p99=$(printf '%s' "$_st" | awk '{ print $7 }')
    _tf="$DNSST_WORKDIR/s/$_ri.times"
    if [ "$_n" = "0" ] || [ -z "$_n" ]; then
      _mean_s="-"; _med_s="-"; _p95_s="-"; _p99_s="-"; _mm="-"
    else
      _mean_s=$(dnsst_fmt_ms "$_mean" "$_tf")
      _med_s=$(dnsst_fmt_ms "$_med" "$_tf")
      _p95_s=$(dnsst_fmt_ms "$_p95" "$_tf")
      _p99_s=$(dnsst_fmt_ms "$_p99" "$_tf")
      _mm="${_min}/${_max}ms"
    fi
    _notes=""
    [ "$_filt" = "none" ] || _notes=$_filt
    if [ -n "${DNSST_FLAG[_ri]:-}" ]; then
      if [ -n "$_notes" ]; then
        _notes="${_notes}, ${DNSST_FLAG[_ri]}"
      else
        _notes=${DNSST_FLAG[_ri]}
      fi
    fi
    printf '%-4s %-14.14s %-22.22s %8s %8s %8s %8s %8s %8s %8s %6s  %s\n' \
      "$_pos" "$_prov" "$_ip" "$_att" "$_rate" \
      "$_mean_s" "$_med_s" "$_p95_s" "$_p99_s" "$_mm" "$_to" "$_notes"
    _pos=$((_pos + 1))
    _k=$((_k + 1))
  done
  printf '\n'
  printf 'Latency columns use only successful DNS responses (NOERROR/NXDOMAIN with a dig Query time).\n'
  printf 'Timeouts are never recorded as 0 ms. Results: %s\n' "$DNSST_OUTDIR"
}

dnsst_write_summary_csv() {
  local _pos _k _ri _att _ok _fail _to _nx _rate _st _n _min _max _mean _med _p95 _p99
  {
    printf '%s\n' "rank,provider,resolver_ip,filtering,service_type,queries,success,failed,timeouts,nxdomain,success_rate_pct,min_ms,max_ms,mean_ms,median_ms,p95_ms,p99_ms,flag,notes"
    _pos=1
    _k=0
    while [ "$_k" -lt "$DNSST_RANK_COUNT" ]; do
      _ri=${DNSST_RANK[_k]}
      _att=$(dnsst_stats_get "$_ri" attempted)
      _ok=$(dnsst_stats_get "$_ri" success)
      _fail=$(dnsst_stats_get "$_ri" failed)
      _to=$(dnsst_stats_get "$_ri" timeout)
      _nx=$(dnsst_stats_get "$_ri" nxdomain)
      _rate=""
      [ "$_att" -gt 0 ] && _rate=$(dnsst_pct "$_ok" "$_att")
      _st=$(dnsst_times_stats "$DNSST_WORKDIR/s/$_ri.times")
      _n=$(printf '%s' "$_st" | awk '{ print $1 }')
      _min=""; _max=""; _mean=""; _med=""; _p95=""; _p99=""
      if [ "$_n" != "0" ] && [ -n "$_n" ]; then
        _min=$(printf '%s' "$_st" | awk '{ print $2 }')
        _max=$(printf '%s' "$_st" | awk '{ print $3 }')
        _mean=$(printf '%s' "$_st" | awk '{ print $4 }')
        _med=$(printf '%s' "$_st" | awk '{ print $5 }')
        _p95=$(printf '%s' "$_st" | awk '{ print $6 }')
        _p99=$(printf '%s' "$_st" | awk '{ print $7 }')
      fi
      dnsst_csv_escape "$_pos"; printf ','
      dnsst_csv_escape "${DNSST_R_PROVIDER[_ri]}"; printf ','
      dnsst_csv_escape "${DNSST_R_IP[_ri]}"; printf ','
      dnsst_csv_escape "${DNSST_R_FILTER[_ri]}"; printf ','
      dnsst_csv_escape "${DNSST_R_SERVICE[_ri]}"; printf ','
      dnsst_csv_escape "$_att"; printf ','
      dnsst_csv_escape "$_ok"; printf ','
      dnsst_csv_escape "$_fail"; printf ','
      dnsst_csv_escape "$_to"; printf ','
      dnsst_csv_escape "$_nx"; printf ','
      dnsst_csv_escape "$_rate"; printf ','
      dnsst_csv_escape "$_min"; printf ','
      dnsst_csv_escape "$_max"; printf ','
      dnsst_csv_escape "$_mean"; printf ','
      dnsst_csv_escape "$_med"; printf ','
      dnsst_csv_escape "$_p95"; printf ','
      dnsst_csv_escape "$_p99"; printf ','
      dnsst_csv_escape "${DNSST_FLAG[_ri]:-}"; printf ','
      dnsst_csv_escape "${DNSST_R_NOTES[_ri]}"
      printf '\n'
      _pos=$((_pos + 1))
      _k=$((_k + 1))
    done
  } > "$DNSST_SUMMARY_CSV"
}

dnsst_write_summary_json() {
  local _k _ri _att _ok _fail _to _nx _rate _st _n _min _max _mean _med _p95 _p99
  {
    printf '{\n'
    printf '  "version": '; dnsst_json_str "$DNSST_VERSION"; printf ',\n'
    printf '  "ranking_rule": '; dnsst_json_str "reliable (success_rate>=${DNSST_RELIABLE_RATE}% and successful>=${DNSST_RELIABLE_MIN_OK}) first, then lower median, then lower p95, then lower mean, then higher success rate"; printf ',\n'
    printf '  "success_definition": '; dnsst_json_str "DNS response with RCODE NOERROR or NXDOMAIN and a dig Query time; timeouts are not 0 ms"; printf ',\n'
    printf '  "resolvers": [\n'
    _k=0
    while [ "$_k" -lt "$DNSST_RANK_COUNT" ]; do
      _ri=${DNSST_RANK[_k]}
      _att=$(dnsst_stats_get "$_ri" attempted)
      _ok=$(dnsst_stats_get "$_ri" success)
      _fail=$(dnsst_stats_get "$_ri" failed)
      _to=$(dnsst_stats_get "$_ri" timeout)
      _nx=$(dnsst_stats_get "$_ri" nxdomain)
      _rate="null"
      [ "$_att" -gt 0 ] && _rate=$(dnsst_pct "$_ok" "$_att")
      _st=$(dnsst_times_stats "$DNSST_WORKDIR/s/$_ri.times")
      _n=$(printf '%s' "$_st" | awk '{ print $1 }')
      _min="null"; _max="null"; _mean="null"; _med="null"; _p95="null"; _p99="null"
      if [ "$_n" != "0" ] && [ -n "$_n" ]; then
        _min=$(printf '%s' "$_st" | awk '{ print $2 }')
        _max=$(printf '%s' "$_st" | awk '{ print $3 }')
        _mean=$(printf '%s' "$_st" | awk '{ print $4 }')
        _med=$(printf '%s' "$_st" | awk '{ print $5 }')
        _p95=$(printf '%s' "$_st" | awk '{ print $6 }')
        _p99=$(printf '%s' "$_st" | awk '{ print $7 }')
      fi
      printf '    {\n'
      printf '      "rank": %s,\n' $((_k + 1))
      printf '      "provider": '; dnsst_json_str "${DNSST_R_PROVIDER[_ri]}"; printf ',\n'
      printf '      "resolver_ip": '; dnsst_json_str "${DNSST_R_IP[_ri]}"; printf ',\n'
      printf '      "filtering": '; dnsst_json_str "${DNSST_R_FILTER[_ri]}"; printf ',\n'
      printf '      "service_type": '; dnsst_json_str "${DNSST_R_SERVICE[_ri]}"; printf ',\n'
      printf '      "notes": '; dnsst_json_str "${DNSST_R_NOTES[_ri]}"; printf ',\n'
      printf '      "queries": %s,\n' "$_att"
      printf '      "success": %s,\n' "$_ok"
      printf '      "failed": %s,\n' "$_fail"
      printf '      "timeouts": %s,\n' "$_to"
      printf '      "nxdomain": %s,\n' "$_nx"
      printf '      "success_rate_pct": %s,\n' "$_rate"
      printf '      "min_ms": %s,\n' "$_min"
      printf '      "max_ms": %s,\n' "$_max"
      printf '      "mean_ms": %s,\n' "$_mean"
      printf '      "median_ms": %s,\n' "$_med"
      printf '      "p95_ms": %s,\n' "$_p95"
      printf '      "p99_ms": %s,\n' "$_p99"
      printf '      "flag": '; dnsst_json_str "${DNSST_FLAG[_ri]:-}"
      printf '\n    }'
      _k=$((_k + 1))
      if [ "$_k" -lt "$DNSST_RANK_COUNT" ]; then
        printf ','
      fi
      printf '\n'
    done
    printf '  ]\n'
    printf '}\n'
  } > "$DNSST_SUMMARY_JSON"
}

dnsst_write_metadata() {
  local _end _stop
  _end=$(dnsst_now_epoch)
  DNSST_END_EPOCH=$_end
  DNSST_ACTUAL_RUNTIME=$((_end - DNSST_START_EPOCH))
  _stop=${DNSST_STOP_REASON:-completed}
  {
    printf 'version=%s\n' "$DNSST_VERSION"
    printf 'start_time=%s\n' "$DNSST_START_ISO"
    printf 'end_time=%s\n' "$(dnsst_iso8601)"
    printf 'os=%s\n' "${DNSST_OS_PRETTY:-$DNSST_PLATFORM}"
    printf 'uname=%s\n' "$(uname -a)"
    printf 'bash_version=%s\n' "$(dnsst_bash_version)"
    printf 'resolver_file=%s\n' "$DNSST_RESOLVER_FILE_USED"
    printf 'domain_source=%s\n' "$DNSST_DOMAIN_SOURCE"
    printf 'requested_domain_count=%s\n' "$DNSST_DOMAIN_COUNT"
    printf 'domain_count_all=%s\n' "$DNSST_DOMAIN_COUNT_ALL"
    printf 'domains_loaded=%s\n' "$DNSST_DOMAIN_N"
    printf 'domains_completed=%s\n' "$DNSST_DOMAINS_DONE"
    printf 'queries_completed=%s\n' "$DNSST_QUERY_TOTAL"
    printf 'query_type=%s\n' "$DNSST_QUERY_TYPE"
    printf 'query_timeout_s=%s\n' "$DNSST_QUERY_TIMEOUT"
    printf 'parallel=%s\n' "$DNSST_PARALLEL"
    printf 'requested_duration_s=%s\n' "$DNSST_DURATION_SECS"
    printf 'actual_runtime_s=%s\n' "$DNSST_ACTUAL_RUNTIME"
    printf 'stop_reason=%s\n' "$_stop"
    printf 'interrupted=%s\n' "${DNSST_INTERRUPTED:-0}"
    printf 'domain_cache_path=%s\n' "${DNSST_DOMAIN_CACHE_PATH:-}"
    printf 'domain_cache_used=%s\n' "${DNSST_DOMAIN_CACHE_USED:-0}"
    printf 'refresh_domains=%s\n' "${DNSST_REFRESH_DOMAINS:-0}"
    printf 'include_disabled=%s\n' "${DNSST_INCLUDE_DISABLED:-0}"
    printf 'probe_enabled=%s\n' "$([ "${DNSST_NO_PROBE:-0}" -eq 1 ] && echo 0 || echo 1)"
    printf 'resolvers_skipped=%s\n' "${DNSST_SKIPPED_COUNT:-0}"
    printf 'skipped_ips=%s\n' "${DNSST_SKIPPED_IPS:-}"
    printf 'dig_command=%s\n' "dig +time=${DNSST_QUERY_TIMEOUT} +tries=1 +retry=0 +nosearch +ignore @IP domain ${DNSST_QUERY_TYPE}"
  } > "$DNSST_META_TXT"

  {
    printf '{\n'
    printf '  "version": '; dnsst_json_str "$DNSST_VERSION"; printf ',\n'
    printf '  "start_time": '; dnsst_json_str "$DNSST_START_ISO"; printf ',\n'
    printf '  "end_time": '; dnsst_json_str "$(dnsst_iso8601)"; printf ',\n'
    printf '  "os": '; dnsst_json_str "${DNSST_OS_PRETTY:-$DNSST_PLATFORM}"; printf ',\n'
    printf '  "uname": '; dnsst_json_str "$(uname -a)"; printf ',\n'
    printf '  "bash_version": '; dnsst_json_str "$(dnsst_bash_version)"; printf ',\n'
    printf '  "resolver_file": '; dnsst_json_str "$DNSST_RESOLVER_FILE_USED"; printf ',\n'
    printf '  "domain_source": '; dnsst_json_str "$DNSST_DOMAIN_SOURCE"; printf ',\n'
    printf '  "requested_domain_count": %s,\n' "$DNSST_DOMAIN_COUNT"
    printf '  "domain_count_all": %s,\n' "$DNSST_DOMAIN_COUNT_ALL"
    printf '  "domains_loaded": %s,\n' "$DNSST_DOMAIN_N"
    printf '  "domains_completed": %s,\n' "$DNSST_DOMAINS_DONE"
    printf '  "queries_completed": %s,\n' "$DNSST_QUERY_TOTAL"
    printf '  "query_type": '; dnsst_json_str "$DNSST_QUERY_TYPE"; printf ',\n'
    printf '  "query_timeout_s": %s,\n' "$DNSST_QUERY_TIMEOUT"
    printf '  "parallel": %s,\n' "$DNSST_PARALLEL"
    printf '  "requested_duration_s": %s,\n' "$DNSST_DURATION_SECS"
    printf '  "actual_runtime_s": %s,\n' "$DNSST_ACTUAL_RUNTIME"
    printf '  "stop_reason": '; dnsst_json_str "$_stop"; printf ',\n'
    printf '  "interrupted": %s,\n' "${DNSST_INTERRUPTED:-0}"
    printf '  "domain_cache_path": '; dnsst_json_str "${DNSST_DOMAIN_CACHE_PATH:-}"; printf ',\n'
    printf '  "domain_cache_used": %s,\n' "${DNSST_DOMAIN_CACHE_USED:-0}"
    printf '  "refresh_domains": %s,\n' "${DNSST_REFRESH_DOMAINS:-0}"
    printf '  "include_disabled": %s,\n' "${DNSST_INCLUDE_DISABLED:-0}"
    printf '  "probe_enabled": %s,\n' "$([ "${DNSST_NO_PROBE:-0}" -eq 1 ] && echo 0 || echo 1)"
    printf '  "resolvers_skipped": %s,\n' "${DNSST_SKIPPED_COUNT:-0}"
    printf '  "skipped_ips": '; dnsst_json_str "${DNSST_SKIPPED_IPS:-}"; printf ',\n'
    printf '  "dig_command": '; dnsst_json_str "dig +time=${DNSST_QUERY_TIMEOUT} +tries=1 +retry=0 +nosearch +ignore @IP domain ${DNSST_QUERY_TYPE}"
    printf '\n}\n'
  } > "$DNSST_META_JSON"
}

dnsst_write_outputs() {
  dnsst_write_summary_csv
  dnsst_write_summary_json
  dnsst_write_metadata
}
