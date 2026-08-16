# shellcheck shell=bash
# Per-resolver statistics and ranking.

# Read a file of integer millisecond samples (one per line).
# Prints: n min max mean median p95 p99
# mean/median may contain a decimal; others are integers or empty.
# Empty file prints: 0
dnsst_times_stats() {
  local _file
  _file=$1
  if [ ! -s "$_file" ]; then
    printf '0\n'
    return 0
  fi
  sort -n "$_file" | awk '
    {
      n++
      a[n] = $1 + 0
      sum += a[n]
    }
    END {
      if (n == 0) { print 0; exit }
      min = a[1]
      max = a[n]
      mean = sum / n
      if (n % 2 == 1) {
        median = a[int(n / 2) + 1]
      } else {
        median = (a[n / 2] + a[n / 2 + 1]) / 2
      }
      p95 = a[pct_idx(95, n)]
      p99 = a[pct_idx(99, n)]
      printf "%d %d %d %.1f %.1f %d %d\n", n, min, max, mean, median, p95, p99
    }
    function pct_idx(p, n,   i) {
      # nearest-rank: ceil(p/100 * n)
      i = int((p / 100.0) * n + 0.999999999)
      if (i < 1) i = 1
      if (i > n) i = n
      return i
    }
  '
}

dnsst_pct() {
  _num=$1
  _den=$2
  if [ -z "$_den" ] || [ "$_den" -eq 0 ]; then
    printf ''
    return 0
  fi
  awk -v n="$_num" -v d="$_den" 'BEGIN { printf "%.1f", (n * 100.0) / d }'
}

# Apply one query result to the per-resolver accumulators.
# Args: resolver_index success qtime_ms error_type
dnsst_stats_record() {
  local _ri _success _qtime _err _base _att _ok _nx _fail _to
  _ri=$1
  _success=$2
  _qtime=$3
  _err=$4
  _base="$DNSST_WORKDIR/s/$_ri"
  _att=$(cat "$_base.attempted" 2>/dev/null || echo 0)
  echo $((_att + 1)) > "$_base.attempted"
  if [ "$_success" = "1" ]; then
    _ok=$(cat "$_base.success" 2>/dev/null || echo 0)
    echo $((_ok + 1)) > "$_base.success"
    if [ -n "$_qtime" ]; then
      printf '%s\n' "$_qtime" >> "$_base.times"
    fi
    printf '%s\n' "$_qtime" > "$_base.last"
    if [ "$_err" = "nxdomain" ]; then
      _nx=$(cat "$_base.nxdomain" 2>/dev/null || echo 0)
      echo $((_nx + 1)) > "$_base.nxdomain"
    fi
  else
    _fail=$(cat "$_base.failed" 2>/dev/null || echo 0)
    echo $((_fail + 1)) > "$_base.failed"
    if [ "$_err" = "timeout" ]; then
      _to=$(cat "$_base.timeout" 2>/dev/null || echo 0)
      echo $((_to + 1)) > "$_base.timeout"
    fi
    printf '%s\n' "" > "$_base.last"
  fi
}

dnsst_stats_get() {
  _f="$DNSST_WORKDIR/s/$1.$2"
  if [ -f "$_f" ]; then
    cat "$_f"
  else
    printf '0'
  fi
}

dnsst_stats_init() {
  dnsst_mkdir_p "$DNSST_WORKDIR/s"
  _i=0
  while [ "$_i" -lt "$DNSST_R_COUNT" ]; do
    : > "$DNSST_WORKDIR/s/$_i.times"
    echo 0 > "$DNSST_WORKDIR/s/$_i.attempted"
    echo 0 > "$DNSST_WORKDIR/s/$_i.success"
    echo 0 > "$DNSST_WORKDIR/s/$_i.failed"
    echo 0 > "$DNSST_WORKDIR/s/$_i.timeout"
    echo 0 > "$DNSST_WORKDIR/s/$_i.nxdomain"
    : > "$DNSST_WORKDIR/s/$_i.last"
    _i=$((_i + 1))
  done
}

# Reliability threshold: documented in PLAN.md / README.
DNSST_RELIABLE_RATE=95
DNSST_RELIABLE_MIN_OK=5

# Write ranking order into DNSST_RANK[] (resolver indexes).
# Also fills DNSST_FLAG[i] with "" or "UNRELIABLE" or "INSUFFICIENT".
dnsst_rank_resolvers() {
  local _rankfile _k _ri _att _ok _st _n _med _p95 _mean _rate _reliable _flag _sorted _row
  DNSST_RANK=()
  DNSST_FLAG=()
  _rankfile="$DNSST_WORKDIR/rank.tsv"
  : > "$_rankfile"
  _k=0
  while [ "$_k" -lt "$DNSST_SEL_COUNT" ]; do
    _ri=${DNSST_SEL[_k]}
    _att=$(dnsst_stats_get "$_ri" attempted)
    _ok=$(dnsst_stats_get "$_ri" success)
    _st=$(dnsst_times_stats "$DNSST_WORKDIR/s/$_ri.times")
    _n=$(printf '%s' "$_st" | awk '{ print $1 }')
    _med=$(printf '%s' "$_st" | awk '{ print $5 }')
    _p95=$(printf '%s' "$_st" | awk '{ print $6 }')
    _mean=$(printf '%s' "$_st" | awk '{ print $4 }')
    _rate=""
    if [ "$_att" -gt 0 ]; then
      _rate=$(dnsst_pct "$_ok" "$_att")
    fi
    _reliable=0
    _flag=""
    if [ "$_ok" -lt "$DNSST_RELIABLE_MIN_OK" ]; then
      _flag="INSUFFICIENT"
    elif [ -n "$_rate" ]; then
      _cmp=$(awk -v r="$_rate" -v t="$DNSST_RELIABLE_RATE" 'BEGIN { print (r+0 < t+0) ? 1 : 0 }')
      if [ "$_cmp" = "1" ]; then
        _flag="UNRELIABLE"
      else
        _reliable=1
      fi
    else
      _flag="INSUFFICIENT"
    fi
    DNSST_FLAG[_ri]=$_flag
    [ -n "$_med" ] || _med=999999999
    [ -n "$_p95" ] || _p95=999999999
    [ -n "$_mean" ] || _mean=999999999
    [ -n "$_rate" ] || _rate=0
    # sort key: reliable desc, median asc, p95 asc, mean asc, rate desc
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$_reliable" "$_med" "$_p95" "$_mean" "$_rate" "$_ri" >> "$_rankfile"
    _k=$((_k + 1))
  done
  DNSST_RANK_COUNT=0
  # sort -k with numeric. rate should be descending so we negate via awk.
  _sorted="$DNSST_WORKDIR/rank.sorted"
  awk -F '\t' '{ printf "%d\t%012.3f\t%012.3f\t%012.3f\t%08.1f\t%s\n", $1, $2, $3, $4, (1000-$5), $6 }' \
    "$_rankfile" | sort -t '	' -k1,1nr -k2,2n -k3,3n -k4,4n -k5,5n > "$_sorted"
  while IFS= read -r _row; do
    _ri=$(printf '%s' "$_row" | awk -F '\t' '{ print $6 }')
    DNSST_RANK[DNSST_RANK_COUNT]=$_ri
    DNSST_RANK_COUNT=$((DNSST_RANK_COUNT + 1))
  done < "$_sorted"
}
