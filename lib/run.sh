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

# Drop resolvers that do not answer a single probe query.
# SERVFAIL/REFUSED/NXDOMAIN still count as reachable.
dnsst_probe_resolvers() {
  local _k _ri _ip _prov _kept _kept_n _skip _batch_end _j _pid _probe_p
  DNSST_SKIPPED_IPS=""
  DNSST_SKIPPED_COUNT=0
  [ "${DNSST_NO_PROBE:-0}" -eq 1 ] && return 0
  [ "$DNSST_SEL_COUNT" -gt 0 ] || return 0

  DNSST_PROBE_DOMAIN=${DNSST_PROBE_DOMAIN:-example.com}
  dnsst_info "Checking reachability of $DNSST_SEL_COUNT resolver(s) via ${DNSST_PROBE_DOMAIN} ..."

  _probe_p=8
  _k=0
  while [ "$_k" -lt "$DNSST_SEL_COUNT" ]; do
    _batch_end=$((_k + _probe_p))
    [ "$_batch_end" -le "$DNSST_SEL_COUNT" ] || _batch_end=$DNSST_SEL_COUNT
    DNSST_WORKER_PIDS=""
    _j=$_k
    while [ "$_j" -lt "$_batch_end" ]; do
      _ri=${DNSST_SEL[_j]}
      (
        if dnsst_resolver_reachable "${DNSST_R_IP[_ri]}"; then
          printf 'ok\n' > "$DNSST_WORKDIR/probe_${_ri}"
        else
          printf 'fail\n' > "$DNSST_WORKDIR/probe_${_ri}"
        fi
      ) &
      DNSST_WORKER_PIDS="$DNSST_WORKER_PIDS $!"
      _j=$((_j + 1))
    done
    for _pid in $DNSST_WORKER_PIDS; do
      wait "$_pid" || true
    done
    DNSST_WORKER_PIDS=""
    _k=$_batch_end
  done

  _kept=""
  _kept_n=0
  _k=0
  while [ "$_k" -lt "$DNSST_SEL_COUNT" ]; do
    _ri=${DNSST_SEL[_k]}
    _ip=${DNSST_R_IP[_ri]}
    _prov=${DNSST_R_PROVIDER[_ri]}
    _skip=1
    if [ -f "$DNSST_WORKDIR/probe_${_ri}" ]; then
      case $(cat "$DNSST_WORKDIR/probe_${_ri}") in
        ok) _skip=0 ;;
      esac
    fi
    if [ "$_skip" -eq 0 ]; then
      if [ -z "$_kept" ]; then
        _kept=$_ri
      else
        _kept="$_kept $_ri"
      fi
      _kept_n=$((_kept_n + 1))
    else
      dnsst_warn "skipping unreachable resolver ${_prov} ${_ip}"
      if [ -z "$DNSST_SKIPPED_IPS" ]; then
        DNSST_SKIPPED_IPS=$_ip
      else
        DNSST_SKIPPED_IPS="$DNSST_SKIPPED_IPS $_ip"
      fi
      DNSST_SKIPPED_COUNT=$((DNSST_SKIPPED_COUNT + 1))
    fi
    _k=$((_k + 1))
  done

  DNSST_SEL=()
  DNSST_SEL_COUNT=0
  for _ri in $_kept; do
    DNSST_SEL[DNSST_SEL_COUNT]=$_ri
    DNSST_SEL_COUNT=$((DNSST_SEL_COUNT + 1))
  done

  dnsst_info "Reachable: $DNSST_SEL_COUNT   skipped: $DNSST_SKIPPED_COUNT"
  if [ "$DNSST_SEL_COUNT" -eq 0 ]; then
    dnsst_die "no reachable resolvers (all $DNSST_SKIPPED_COUNT failed the probe). Check network, IPv6, or pass --no-probe."
  fi
}

dnsst_run_benchmark() {
  local _di
  dnsst_probe_resolvers
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
