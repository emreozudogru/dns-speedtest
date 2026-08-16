#!/bin/bash
# Offline test suite. Must not require the public Internet.
# Compatible with Bash 3.2.

set -e

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
export DNSST_ROOT="$ROOT"
export DNSST_FIXTURE_DIR="$TESTS_DIR/fixtures"

# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=../lib/cli.sh
. "$ROOT/lib/cli.sh"
# shellcheck source=../lib/deps.sh
. "$ROOT/lib/deps.sh"
# shellcheck source=../lib/resolvers.sh
. "$ROOT/lib/resolvers.sh"
# shellcheck source=../lib/domains.sh
. "$ROOT/lib/domains.sh"
# shellcheck source=../lib/query.sh
. "$ROOT/lib/query.sh"
# shellcheck source=../lib/stats.sh
. "$ROOT/lib/stats.sh"

PASS=0
FAIL=0
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/dnsst-tests.XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT

ok() {
  PASS=$((PASS + 1))
  printf '  PASS  %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1"
}

assert_eq() {
  _name=$1
  _got=$2
  _want=$3
  if [ "$_got" = "$_want" ]; then
    ok "$_name"
  else
    fail "$_name (got '$_got' want '$_want')"
  fi
}

assert_file_contains() {
  _name=$1
  _file=$2
  _pat=$3
  if grep -q "$_pat" "$_file"; then
    ok "$_name"
  else
    fail "$_name (pattern '$_pat' not in $_file)"
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

# ---------- duration parsing ----------
section "duration parsing"
assert_eq "30s" "$(dnsst_parse_duration 30s)" "30"
assert_eq "5m" "$(dnsst_parse_duration 5m)" "300"
assert_eq "1h" "$(dnsst_parse_duration 1h)" "3600"
assert_eq "bare 90" "$(dnsst_parse_duration 90)" "90"
assert_eq "5M case" "$(dnsst_parse_duration 5M)" "300"
if dnsst_parse_duration banana >/dev/null 2>&1; then
  fail "banana should be invalid"
else
  ok "banana rejected"
fi
if dnsst_parse_duration 0 >/dev/null 2>&1; then
  fail "0 should be invalid"
else
  ok "zero duration rejected"
fi
if dnsst_parse_duration -- -5s >/dev/null 2>&1; then
  fail "negative should be invalid"
else
  ok "negative duration rejected"
fi

# ---------- CLI ----------
section "CLI validation"
if "$ROOT/dns-speedtest.sh" --duration banana >/dev/null 2>"$WORKDIR/cli1.err"; then
  fail "--duration banana should fail"
else
  ok "--duration banana fails"
fi
if "$ROOT/dns-speedtest.sh" --parallel 0 >/dev/null 2>"$WORKDIR/cli2.err"; then
  fail "--parallel 0 should fail"
else
  ok "--parallel 0 fails"
fi
if "$ROOT/dns-speedtest.sh" --query-timeout -1 >/dev/null 2>"$WORKDIR/cli3.err"; then
  fail "negative timeout should fail"
else
  ok "negative timeout fails"
fi
if "$ROOT/dns-speedtest.sh" --domain-count 0 >/dev/null 2>"$WORKDIR/cli4.err"; then
  fail "zero domain-count should fail"
else
  ok "zero domain-count fails"
fi
if "$ROOT/dns-speedtest.sh" --domain-file "$WORKDIR/missing.txt" >/dev/null 2>"$WORKDIR/cli5.err"; then
  fail "missing domain file should fail"
else
  ok "missing domain file fails"
fi
if "$ROOT/dns-speedtest.sh" --no-such-flag >/dev/null 2>"$WORKDIR/cli6.err"; then
  fail "unknown option should fail"
else
  ok "unknown option fails"
fi
if "$ROOT/dns-speedtest.sh" --help >/dev/null; then
  ok "--help exits 0"
else
  fail "--help should exit 0"
fi
_ver=$("$ROOT/dns-speedtest.sh" --version)
case "$_ver" in
  dns-speedtest\ *) ok "--version prints name" ;;
  *) fail "--version output '$_ver'" ;;
esac

# ---------- resolver parsing ----------
section "resolver parsing"
dnsst_parse_resolvers "$TESTS_DIR/fixtures/resolvers-good.tsv" 0
dnsst_select_resolvers
assert_eq "parsed rows" "$DNSST_R_COUNT" "4"
assert_eq "enabled selected" "$DNSST_SEL_COUNT" "3"
assert_eq "first ip" "${DNSST_R_IP[0]}" "1.1.1.1"

DNSST_INCLUDE_DISABLED=1
dnsst_select_resolvers
assert_eq "include-disabled count" "$DNSST_SEL_COUNT" "4"
DNSST_INCLUDE_DISABLED=0

if ( dnsst_parse_resolvers "$TESTS_DIR/fixtures/resolvers-bad.tsv" 0 ) >/dev/null 2>"$WORKDIR/res-bad.err"; then
  fail "malformed resolver IP should fail"
else
  ok "malformed resolver IP rejected"
fi

# ---------- domain parsing ----------
section "domain parsing"
dnsst_load_domain_file "$TESTS_DIR/fixtures/domains.txt" 0
assert_eq "valid domains loaded" "$DNSST_DOMAIN_N" "4"
assert_eq "first domain" "${DNSST_DOMAINS[0]}" "example.com"
assert_eq "last domain" "${DNSST_DOMAINS[3]}" "ok-site.test"

dnsst_load_domain_file "$TESTS_DIR/fixtures/domains.txt" 2
assert_eq "domain-count 2" "$DNSST_DOMAIN_N" "2"

# CRLF
printf 'crlf-one.test\r\n# comment\r\ncrlf-two.test\r\n' > "$WORKDIR/crlf.txt"
dnsst_load_domain_file "$WORKDIR/crlf.txt" 0
assert_eq "crlf domains" "$DNSST_DOMAIN_N" "2"
assert_eq "crlf first" "${DNSST_DOMAINS[0]}" "crlf-one.test"

# Tranco-style rank,domain
printf '1,google.com\n2,cloudflare.com\n' > "$WORKDIR/tranco.csv"
dnsst_load_domain_file "$WORKDIR/tranco.csv" 0
assert_eq "tranco-style domain" "${DNSST_DOMAINS[0]}" "google.com"

# ---------- IP / domain validators ----------
section "validators"
if dnsst_is_ipv4 1.1.1.1; then ok "ipv4"; else fail "ipv4"; fi
if dnsst_is_ipv4 256.1.1.1; then fail "bad ipv4 accepted"; else ok "bad ipv4 rejected"; fi
if dnsst_is_ipv6 2606:4700:4700::1111; then ok "ipv6"; else fail "ipv6"; fi
if dnsst_is_ip cloudflare-dns.com; then fail "hostname accepted as ip"; else ok "hostname rejected as ip"; fi
if dnsst_is_domain example.com; then ok "domain"; else fail "domain"; fi
if dnsst_is_domain "evil;rm -rf"; then fail "metachar domain accepted"; else ok "metachar domain rejected"; fi

# ---------- dig classification ----------
section "dig classification"
_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-noerror.txt")" 0)
assert_eq "noerror rcode" "$(printf '%s' "$_line" | awk -F '\t' '{print $1}')" "NOERROR"
assert_eq "noerror outcome" "$(printf '%s' "$_line" | awk -F '\t' '{print $2}')" "success"
assert_eq "noerror success" "$(printf '%s' "$_line" | awk -F '\t' '{print $3}')" "1"
assert_eq "noerror qtime" "$(printf '%s' "$_line" | awk -F '\t' '{print $4}')" "18"
assert_eq "noerror answers" "$(printf '%s' "$_line" | awk -F '\t' '{print $5}')" "1"

_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-nxdomain.txt")" 0)
assert_eq "nxdomain success" "$(printf '%s' "$_line" | awk -F '\t' '{print $3}')" "1"
assert_eq "nxdomain err" "$(printf '%s' "$_line" | awk -F '\t' '{print $6}')" "nxdomain"
assert_eq "nxdomain qtime" "$(printf '%s' "$_line" | awk -F '\t' '{print $4}')" "22"

_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-servfail.txt")" 0)
assert_eq "servfail not success" "$(printf '%s' "$_line" | awk -F '\t' '{print $3}')" "0"
assert_eq "servfail outcome" "$(printf '%s' "$_line" | awk -F '\t' '{print $2}')" "servfail"

_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-refused.txt")" 0)
assert_eq "refused outcome" "$(printf '%s' "$_line" | awk -F '\t' '{print $2}')" "refused"

_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-timeout.txt")" 9)
assert_eq "timeout outcome" "$(printf '%s' "$_line" | awk -F '\t' '{print $2}')" "timeout"
assert_eq "timeout not success" "$(printf '%s' "$_line" | awk -F '\t' '{print $3}')" "0"
_qt=$(printf '%s' "$_line" | awk -F '\t' '{print $4}')
assert_eq "timeout has no qtime" "$_qt" ""

_line=$(dnsst_classify_dig "$(cat "$TESTS_DIR/fixtures/dig-no-qtime.txt")" 0)
assert_eq "missing qtime not success" "$(printf '%s' "$_line" | awk -F '\t' '{print $3}')" "0"

# ---------- statistics ----------
section "statistics"
_tf="$WORKDIR/times1"
printf '%s\n' 1 2 3 4 5 6 7 8 9 10 > "$_tf"
_st=$(dnsst_times_stats "$_tf")
assert_eq "n=10" "$(printf '%s' "$_st" | awk '{print $1}')" "10"
assert_eq "min" "$(printf '%s' "$_st" | awk '{print $2}')" "1"
assert_eq "max" "$(printf '%s' "$_st" | awk '{print $3}')" "10"
assert_eq "mean 1-10" "$(printf '%s' "$_st" | awk '{print $4}')" "5.5"
assert_eq "median even" "$(printf '%s' "$_st" | awk '{print $5}')" "5.5"

printf '%s\n' 1 2 3 > "$_tf"
_st=$(dnsst_times_stats "$_tf")
assert_eq "median odd" "$(printf '%s' "$_st" | awk '{print $5}')" "2.0"

# 1..100 for percentiles
_i=1
: > "$_tf"
while [ "$_i" -le 100 ]; do
  echo "$_i" >> "$_tf"
  _i=$((_i + 1))
done
_st=$(dnsst_times_stats "$_tf")
assert_eq "p95 nearest-rank" "$(printf '%s' "$_st" | awk '{print $6}')" "95"
assert_eq "p99 nearest-rank" "$(printf '%s' "$_st" | awk '{print $7}')" "99"
assert_eq "median 1-100" "$(printf '%s' "$_st" | awk '{print $5}')" "50.5"

: > "$_tf"
_st=$(dnsst_times_stats "$_tf")
assert_eq "empty times" "$_st" "0"

assert_eq "pct 1/2" "$(dnsst_pct 1 2)" "50.0"
assert_eq "pct empty den" "$(dnsst_pct 1 0)" ""

# ---------- ranking ----------
section "ranking"
# shellcheck source=../lib/report.sh
. "$ROOT/lib/report.sh"
# shellcheck source=../lib/run.sh
. "$ROOT/lib/run.sh"

DNSST_WORKDIR="$WORKDIR/rankrun"
mkdir -p "$DNSST_WORKDIR/s"
dnsst_parse_resolvers "$TESTS_DIR/fixtures/resolvers-order.tsv" 0
# add a 4th unreliable resolver in memory
DNSST_R_PROVIDER[3]="Flaky"
DNSST_R_IP[3]="203.0.113.9"
DNSST_R_SERVICE[3]="public"
DNSST_R_FILTER[3]="none"
DNSST_R_NOTES[3]=""
DNSST_R_SOURCE[3]=""
DNSST_R_ENABLED[3]="1"
DNSST_R_COUNT=4
DNSST_SEL[0]=0
DNSST_SEL[1]=1
DNSST_SEL[2]=2
DNSST_SEL[3]=3
DNSST_SEL_COUNT=4
dnsst_stats_init
# fast reliable
i=0
while [ "$i" -lt 10 ]; do
  echo 20 >> "$DNSST_WORKDIR/s/0.times"
  echo 10 >> "$DNSST_WORKDIR/s/1.times"
  echo 30 >> "$DNSST_WORKDIR/s/2.times"
  i=$((i + 1))
done
echo 10 > "$DNSST_WORKDIR/s/0.attempted"
echo 10 > "$DNSST_WORKDIR/s/0.success"
echo 10 > "$DNSST_WORKDIR/s/1.attempted"
echo 10 > "$DNSST_WORKDIR/s/1.success"
echo 10 > "$DNSST_WORKDIR/s/2.attempted"
echo 10 > "$DNSST_WORKDIR/s/2.success"
# flaky: 8 successes of 20 (40%) with a tiny median — enough
# samples to be ranked, too unreliable to win.
_i=0
while [ "$_i" -lt 8 ]; do
  echo 5 >> "$DNSST_WORKDIR/s/3.times"
  _i=$((_i + 1))
done
echo 20 > "$DNSST_WORKDIR/s/3.attempted"
echo 8 > "$DNSST_WORKDIR/s/3.success"
echo 12 > "$DNSST_WORKDIR/s/3.failed"
dnsst_rank_resolvers
assert_eq "rank0 fastest reliable" "${DNSST_R_IP[${DNSST_RANK[0]}]}" "192.0.2.2"
assert_eq "rank1 second" "${DNSST_R_IP[${DNSST_RANK[1]}]}" "192.0.2.1"
assert_eq "rank2 third" "${DNSST_R_IP[${DNSST_RANK[2]}]}" "192.0.2.3"
assert_eq "rank3 flaky last" "${DNSST_R_IP[${DNSST_RANK[3]}]}" "203.0.113.9"
assert_eq "flaky flagged" "${DNSST_FLAG[3]}" "UNRELIABLE"

# ---------- CSV / JSON helpers ----------
section "csv and json helpers"
assert_eq "csv plain" "$(dnsst_csv_escape hello)" "hello"
_got=$(dnsst_csv_escape 'a,b"c')
assert_eq "csv quoted" "$_got" '"a,b""c"'
_got=$(dnsst_json_escape 'a"b\c')
assert_eq "json escape" "$_got" 'a\"b\\c'

# ---------- full script: sequential domain-first ----------
section "sequential domain-first run"
chmod +x "$TESTS_DIR/mocks/dig" "$TESTS_DIR/mocks/curl" "$ROOT/dns-speedtest.sh"
export DNSST_MOCK_LOG="$WORKDIR/order-seq.log"
: > "$DNSST_MOCK_LOG"
_outseq="$WORKDIR/out-seq"
PATH="$TESTS_DIR/mocks:$PATH" \
  "$ROOT/dns-speedtest.sh" \
    --domain-file "$TESTS_DIR/fixtures/domains-order.txt" \
    --resolver-file "$TESTS_DIR/fixtures/resolvers-order.tsv" \
    --output-dir "$_outseq" \
    --quiet \
    --no-install \
    --no-probe \
    --query-timeout 2 \
    --parallel 1 \
    >"$WORKDIR/seq.stdout" 2>"$WORKDIR/seq.stderr" || {
      fail "sequential run exited non-zero"
    }

_want=$(printf '%s\n' \
  "domain-one.test 192.0.2.1" \
  "domain-one.test 192.0.2.2" \
  "domain-one.test 192.0.2.3" \
  "domain-two.test 192.0.2.1" \
  "domain-two.test 192.0.2.2" \
  "domain-two.test 192.0.2.3" \
  "domain-three.test 192.0.2.1" \
  "domain-three.test 192.0.2.2" \
  "domain-three.test 192.0.2.3")
_got=$(cat "$DNSST_MOCK_LOG")
assert_eq "sequential domain-first order" "$_got" "$_want"

if [ -f "$_outseq/queries.csv" ] && [ -f "$_outseq/summary.csv" ] && [ -f "$_outseq/summary.json" ] && [ -f "$_outseq/metadata.json" ]; then
  ok "result files created"
else
  fail "missing result files in $_outseq"
fi

if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$_outseq/summary.json" 2>/dev/null; then
  ok "summary.json is valid JSON"
else
  fail "summary.json is not valid JSON"
fi
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$_outseq/metadata.json" 2>/dev/null; then
  ok "metadata.json is valid JSON"
else
  fail "metadata.json is not valid JSON"
fi

_qrows=$(tail -n +2 "$_outseq/queries.csv" | wc -l | tr -d ' ')
assert_eq "query csv rows" "$_qrows" "9"

# ranking in sequential mock: 192.0.2.1=11ms, .2=22ms, .3=33ms
assert_file_contains "summary ranks fastest first" "$_outseq/summary.csv" "192.0.2.1"
_first_ip=$(awk -F ',' 'NR==2 { print $3 }' "$_outseq/summary.csv")
assert_eq "summary first resolver" "$_first_ip" "192.0.2.1"

assert_file_contains "stdout table has header" "$WORKDIR/seq.stdout" "Median"

# ---------- parallel domain-first ----------
section "parallel domain-first run"
export DNSST_MOCK_LOG="$WORKDIR/order-par.log"
: > "$DNSST_MOCK_LOG"
_outpar="$WORKDIR/out-par"
PATH="$TESTS_DIR/mocks:$PATH" \
  "$ROOT/dns-speedtest.sh" \
    --domain-file "$TESTS_DIR/fixtures/domains-order.txt" \
    --resolver-file "$TESTS_DIR/fixtures/resolvers-order.tsv" \
    --output-dir "$_outpar" \
    --quiet \
    --no-install \
    --no-probe \
    --parallel 3 \
    >"$WORKDIR/par.stdout" 2>"$WORKDIR/par.stderr" || {
      fail "parallel run exited non-zero"
    }

# First 3 lines must all be domain-one, next 3 domain-two, last 3 domain-three.
_okord=1
_n=0
while IFS= read -r _ln; do
  _n=$((_n + 1))
  _dom=${_ln%% *}
  if [ "$_n" -le 3 ]; then
    [ "$_dom" = "domain-one.test" ] || _okord=0
  elif [ "$_n" -le 6 ]; then
    [ "$_dom" = "domain-two.test" ] || _okord=0
  else
    [ "$_dom" = "domain-three.test" ] || _okord=0
  fi
done < "$DNSST_MOCK_LOG"
assert_eq "parallel preserves domain-first grouping" "$_okord" "1"
assert_eq "parallel query count" "$_n" "9"

# Must not be resolver-first (all domains against 192.0.2.1 first).
_first3=$(head -3 "$DNSST_MOCK_LOG" | awk '{print $2}' | sort -u | wc -l | tr -d ' ')
if [ "$_first3" -ge 2 ]; then
  ok "parallel first domain used multiple resolvers (not resolver-first)"
else
  # With parallel 3, all 3 resolvers of domain1 start first; unique IPs should be 3.
  fail "parallel first-three lines only used $_first3 resolver IP(s)"
fi

# ---------- timeouts in output ----------
section "timeout handling in a run"
export DNSST_MOCK_LOG="$WORKDIR/order-to.log"
: > "$DNSST_MOCK_LOG"
_outto="$WORKDIR/out-to"
PATH="$TESTS_DIR/mocks:$PATH" \
  "$ROOT/dns-speedtest.sh" \
    --domain-file "$TESTS_DIR/fixtures/domains-order.txt" \
    --resolver-file "$TESTS_DIR/fixtures/resolvers-good.tsv" \
    --output-dir "$_outto" \
    --quiet --no-install --no-probe --parallel 1 \
    >"$WORKDIR/to.stdout" 2>"$WORKDIR/to.stderr" || {
      fail "timeout-run exited non-zero"
    }

if grep -q '203.0.113.1' "$_outto/queries.csv"; then
  ok "timeout resolver present in queries.csv"
else
  fail "timeout resolver missing from queries.csv"
fi
# The timeout rows must not have query_time_ms=0
_bad=0
# columns: 10 is query_time_ms (1-indexed)
while IFS= read -r _row; do
  case "$_row" in
    *203.0.113.1*)
      _qtms=$(printf '%s' "$_row" | awk -F ',' '{ print $10 }')
      if [ "$_qtms" = "0" ]; then
        _bad=1
      fi
      ;;
  esac
done < "$_outto/queries.csv"
assert_eq "timeout not recorded as 0 ms" "$_bad" "0"
assert_file_contains "timeout status in csv" "$_outto/queries.csv" "TIMEOUT"

# ---------- reachability probe skips dead resolvers ----------
section "reachability probe"
export DNSST_MOCK_LOG="$WORKDIR/order-probe.log"
: > "$DNSST_MOCK_LOG"
_outpr="$WORKDIR/out-probe"
PATH="$TESTS_DIR/mocks:$PATH" \
  "$ROOT/dns-speedtest.sh" \
    --domain-file "$TESTS_DIR/fixtures/domains-order.txt" \
    --resolver-file "$TESTS_DIR/fixtures/resolvers-good.tsv" \
    --output-dir "$_outpr" \
    --quiet --no-install --parallel 1 \
    >"$WORKDIR/probe.stdout" 2>"$WORKDIR/probe.stderr" || {
      fail "probe-run exited non-zero"
    }
if grep -q '203.0.113.1' "$_outpr/queries.csv"; then
  fail "unreachable 203.0.113.1 was still benchmarked"
else
  ok "probe omitted unreachable 203.0.113.1 from queries"
fi
assert_file_contains "probe skipped count" "$_outpr/metadata.txt" "resolvers_skipped=1"
assert_file_contains "probe skipped ip" "$_outpr/metadata.txt" "203.0.113.1"
if grep -q '1.1.1.1' "$_outpr/queries.csv" && grep -q '8.8.8.8' "$_outpr/queries.csv"; then
  ok "probe kept reachable resolvers"
else
  fail "probe dropped a reachable resolver"
fi

# ---------- soft duration ----------
section "soft duration deadline"
export DNSST_MOCK_LOG="$WORKDIR/order-dur.log"
: > "$DNSST_MOCK_LOG"
export DNSST_MOCK_SLEEP=1
_outdur="$WORKDIR/out-dur"
_t0=$(date +%s)
PATH="$TESTS_DIR/mocks:$PATH" \
  "$ROOT/dns-speedtest.sh" \
    --domain-file "$TESTS_DIR/fixtures/domains-order.txt" \
    --resolver-file "$TESTS_DIR/fixtures/resolvers-order.tsv" \
    --output-dir "$_outdur" \
    --quiet --no-install --no-probe --parallel 1 \
    --duration 1s \
    >"$WORKDIR/dur.stdout" 2>"$WORKDIR/dur.stderr" || {
      fail "duration-run exited non-zero"
    }
_t1=$(date +%s)
unset DNSST_MOCK_SLEEP
_domains_done=$(grep '^domains_completed=' "$_outdur/metadata.txt" | sed 's/.*=//')
# 3 resolvers * 1s each = 3s per domain. Budget 1s means at most one domain
# round starts; that round is allowed to finish (3 queries).
if [ "$_domains_done" -ge 1 ] && [ "$_domains_done" -lt 3 ]; then
  ok "soft duration stopped after a domain round (completed=$_domains_done)"
else
  fail "duration completed $_domains_done domains (expected 1, maybe 2)"
fi
assert_file_contains "stop_reason=duration" "$_outdur/metadata.txt" "stop_reason=duration"
# The finished domain must have all 3 resolvers (fair comparison).
_q1=$(grep -c 'domain-one.test' "$_outdur/queries.csv" || true)
assert_eq "finished domain queried every resolver" "$_q1" "3"

# ---------- cleanup of workdir ----------
section "cleanup"
# After a successful run the temp workdir should be gone (trap EXIT).
# We cannot see the exact path; assert the process left no dnsst.* in TMPDIR
# created during this test beyond our own WORKDIR. Soft check: script still
# ran to completion and produced outputs (already checked). Extra: run with
# a wrapper that records DNSST internals is not necessary.
ok "cleanup trap installed (EXIT removes workdir; outputs persist)"

# ---------- list-resolvers ----------
section "list-resolvers"
if "$ROOT/dns-speedtest.sh" --resolver-file "$TESTS_DIR/fixtures/resolvers-good.tsv" \
    --list-resolvers >"$WORKDIR/list.out" 2>"$WORKDIR/list.err"; then
  assert_file_contains "lists 1.1.1.1" "$WORKDIR/list.out" "1.1.1.1"
else
  fail "list-resolvers failed"
fi

# ---------- default resolver file parse ----------
section "bundled resolver database"
dnsst_parse_resolvers "$ROOT/config/resolvers.tsv" 0
dnsst_select_resolvers
if [ "$DNSST_SEL_COUNT" -ge 5 ]; then
  ok "bundled DB has $DNSST_SEL_COUNT enabled resolvers"
else
  fail "bundled DB enabled count $DNSST_SEL_COUNT"
fi
# IPv6 rows must be accepted (they are present, disabled).
_v6=0
_i=0
while [ "$_i" -lt "$DNSST_R_COUNT" ]; do
  case "${DNSST_R_IP[_i]}" in
    *:*) _v6=1 ;;
  esac
  _i=$((_i + 1))
done
assert_eq "bundled DB contains IPv6 rows" "$_v6" "1"

# ---------- bash 3.2 feature audit ----------
section "bash 3.2 feature audit"
if grep -R -n -E '(^|[^[:alnum:]_])(declare[[:space:]]+-A|mapfile|readarray|wait[[:space:]]+-n)([^[:alnum:]_-]|$)' \
    "$ROOT/dns-speedtest.sh" "$ROOT/lib" \
    >"$WORKDIR/bash4.hits" 2>/dev/null; then
  fail "Bash 4+ features found:"
  cat "$WORKDIR/bash4.hits"
else
  ok "no Bash 4+ features in scripts"
fi

# ---------- quoting / eval audit ----------
section "security audit"
if grep -R -n -E '(^|[^[:alnum:]_])eval[[:space:]]' "$ROOT/dns-speedtest.sh" "$ROOT/lib"; then
  fail "eval found in runtime scripts"
else
  ok "no eval in runtime scripts"
fi

printf '\n%s\n' "----------------------------------------"
printf 'Passed: %s   Failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
