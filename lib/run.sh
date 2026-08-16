# shellcheck shell=bash
# Domain-first benchmark engine. Sequential by default.
# Parallelism is per-domain only (batch + wait PID; no Bash 4 wait-n).

DNSST_INTERRUPTED=0
DNSST_STOP_REASON="completed"
DNSST_WORKER_PIDS=""

dnsst_cleanup() {
  _ec=$?
  if [ -n "${DNSST_WORKER_PIDS:-}" ]; then
    for _p in $DNSST_WORKER_PIDS; do
      kill "$_p" 2>/dev/null || true
    done
    DNSST_WORKER_PIDS=""
  fi
  if [ -n "${DNSST_WORKDIR:-}" ] && [ -d "${DNSST_WORKDIR:-}" ]; then
    rm -rf "$DNSST_WORKDIR"
  fi
  return "$_ec"
}

dnsst_on_signal() {
  DNSST_INTERRUPTED=1
  DNSST_STOP_REASON="interrupted"
  if [ -n "${DNSST_WORKER_PIDS:-}" ]; then
    for _p in $DNSST_WORKER_PIDS; do
      kill "$_p" 2>/dev/null || true
    done
  fi
}

dnsst_deadline_reached() {
  local _now
  [ "${DNSST_DURATION_SECS:-0}" -gt 0 ] || return 1
  _now=$(dnsst_now_epoch)
  [ "$_now" -ge "$DNSST_DEADLINE_EPOCH" ]
}

# Run every selected resolver against one domain, in batches of --parallel.
dnsst_run_domain_round() {
  local _domain _di _k _j _ri _rf _pid _batch_end
  _domain=$1
  _di=$2
  DNSST_CURRENT_DOMAIN=$_domain
  _k=0
  while [ "$_k" -lt "$DNSST_SEL_COUNT" ]; do
    [ "$DNSST_INTERRUPTED" -eq 0 ] || return 1
    _batch_end=$((_k + DNSST_PARALLEL))
    [ "$_batch_end" -le "$DNSST_SEL_COUNT" ] || _batch_end=$DNSST_SEL_COUNT

    DNSST_WORKER_PIDS=""
    _j=$_k
    while [ "$_j" -lt "$_batch_end" ]; do
      _ri=${DNSST_SEL[_j]}
      _rf="$DNSST_WORKDIR/q/${_di}_${_ri}.tsv"
      if [ "$DNSST_PARALLEL" -eq 1 ]; then
        dnsst_query_worker "$_rf" "$_domain" "$_ri" "$DNSST_START_EPOCH"
        dnsst_ingest_result "$_rf" "$_ri"
      else
        dnsst_query_worker "$_rf" "$_domain" "$_ri" "$DNSST_START_EPOCH" &
        _pid=$!
        DNSST_WORKER_PIDS="$DNSST_WORKER_PIDS $_pid"
        DNSST_W_RI[_pid]=$_ri
        DNSST_W_RF[_pid]=$_rf
      fi
      _j=$((_j + 1))
    done

    if [ "$DNSST_PARALLEL" -gt 1 ]; then
      for _pid in $DNSST_WORKER_PIDS; do
        wait "$_pid" || true
        _ri=${DNSST_W_RI[_pid]}
        _rf=${DNSST_W_RF[_pid]}
        dnsst_ingest_result "$_rf" "$_ri"
      done
      DNSST_WORKER_PIDS=""
    fi

    dnsst_maybe_live_stats
    _k=$_batch_end
  done
  DNSST_DOMAINS_DONE=$((DNSST_DOMAINS_DONE + 1))
  return 0
}

dnsst_run_benchmark() {
  local _di
  DNSST_START_EPOCH=$(dnsst_now_epoch)
  DNSST_START_ISO=$(dnsst_iso8601)
  if [ "$DNSST_DURATION_SECS" -gt 0 ]; then
    DNSST_DEADLINE_EPOCH=$((DNSST_START_EPOCH + DNSST_DURATION_SECS))
  else
    DNSST_DEADLINE_EPOCH=0
  fi

  dnsst_info "Resolvers: $DNSST_SEL_COUNT   domains: $DNSST_DOMAIN_N   parallel: $DNSST_PARALLEL   query-timeout: ${DNSST_QUERY_TIMEOUT}s"
  if [ "$DNSST_DURATION_SECS" -gt 0 ]; then
    dnsst_info "Soft duration budget: $(dnsst_format_duration "$DNSST_DURATION_SECS") (in-flight domain rounds are allowed to finish)"
  fi
  if [ "$DNSST_PARALLEL" -gt 1 ]; then
    dnsst_info "Parallel mode is optional: concurrency can change measured latency. Prefer --parallel 1 for the cleanest comparison."
  fi

  _di=0
  while [ "$_di" -lt "$DNSST_DOMAIN_N" ]; do
    if [ "$DNSST_INTERRUPTED" -eq 1 ]; then
      break
    fi
    if dnsst_deadline_reached; then
      DNSST_STOP_REASON="duration"
      dnsst_info "Duration budget reached; not starting another domain round."
      break
    fi
    dnsst_run_domain_round "${DNSST_DOMAINS[_di]}" "$_di" || true
    if [ "$DNSST_INTERRUPTED" -eq 1 ]; then
      break
    fi
    _di=$((_di + 1))
  done

  if [ "$DNSST_INTERRUPTED" -eq 1 ]; then
    dnsst_info "Interrupted by signal; writing partial results."
  fi

  # Final live snapshot so the last numbers are visible, then a blank line
  # so the ranking table does not overwrite it on a TTY.
  if [ "${DNSST_QUIET:-0}" -eq 0 ]; then
    DNSST_LAST_STATS_AT=0
    dnsst_maybe_live_stats
    if [ "$DNSST_USE_TTY" -eq 1 ]; then
      printf '\n' >&2
      DNSST_TTY_LINES=0
    fi
  fi

  dnsst_print_final_table
  dnsst_write_outputs
}
