# shellcheck shell=bash
# Command-line parsing and help text.

dnsst_usage() {
  cat <<'EOF'
dns-speedtest — measure DNS query time of public (or custom) resolvers

USAGE
  dns-speedtest.sh [options]

OPTIONS
  --duration DUR           Soft global testing budget (30s, 5m, 1h, or seconds).
                           Omit to test the entire selected domain list.
  --parallel N             Concurrent resolver queries per domain (default: 1).
  --query-timeout SEC      Per-query dig timeout in seconds (default: 2).
  --stats-interval DUR     Live progress interval (default: 5s).
  --domain-count N         Use the first N valid domains (default: 1000).
                           Pass "all" to use every valid domain in the source.
  --domain-file FILE       Use this domain list instead of downloading Tranco.
  --resolver-file FILE     Resolver TSV (default: config/resolvers.tsv).
  --refresh-domains        Re-download the Tranco list even if a cache exists.
  --output-dir DIR         Write results here (default: results/YYYYMMDD-HHMMSS).
  --query-type TYPE        DNS query type (default: A).
  --include-disabled       Also test resolvers marked disabled in the TSV.
  --no-probe               Skip the pre-run reachability check (test every resolver).
  --list-resolvers         Print the parsed resolver list and exit.
  --yes, -y                Auto-approve installing a missing required package.
  --no-install             Never attempt to install missing packages.
  --quiet, -q              Suppress live progress (final report is still printed).
  --help, -h               Show this help.
  --version, -V            Show version.

DURATION SEMANTICS
  --duration is a SOFT deadline. A domain round that has already started
  is allowed to finish against every selected resolver so the comparison
  stays fair. In-flight dig processes are not killed when the budget
  expires. Wall-clock runtime may therefore slightly exceed DUR.

EXAMPLES
  ./dns-speedtest.sh
  ./dns-speedtest.sh --duration 5m
  ./dns-speedtest.sh --duration 5m --parallel 4
  ./dns-speedtest.sh --domain-count 10000
  ./dns-speedtest.sh --resolver-file my-resolvers.tsv
  ./dns-speedtest.sh --domain-file domains.txt
  ./dns-speedtest.sh --refresh-domains
  ./dns-speedtest.sh --yes
EOF
}

dnsst_cli_defaults() {
  DNSST_DURATION_RAW=""
  DNSST_DURATION_SECS=0
  DNSST_PARALLEL=1
  DNSST_QUERY_TIMEOUT=2
  DNSST_STATS_INTERVAL_RAW="5s"
  DNSST_STATS_INTERVAL_SECS=5
  DNSST_DOMAIN_COUNT=1000
  DNSST_DOMAIN_COUNT_ALL=0
  DNSST_DOMAIN_FILE=""
  DNSST_RESOLVER_FILE=""
  DNSST_REFRESH_DOMAINS=0
  DNSST_OUTPUT_DIR=""
  DNSST_QUERY_TYPE="A"
  DNSST_INCLUDE_DISABLED=0
  DNSST_NO_PROBE=0
  DNSST_LIST_RESOLVERS=0
  DNSST_YES=0
  DNSST_NO_INSTALL=0
  DNSST_QUIET=0
}

dnsst_cli_need_arg() {
  if [ -z "${2:-}" ]; then
    dnsst_die "option $1 requires a value"
  fi
}

dnsst_parse_args() {
  dnsst_cli_defaults
  while [ $# -gt 0 ]; do
    _opt=$1
    case "$_opt" in
      --duration)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_DURATION_RAW=$2
        shift 2
        ;;
      --duration=*)
        DNSST_DURATION_RAW=${_opt#--duration=}
        shift
        ;;
      --parallel)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_PARALLEL=$2
        shift 2
        ;;
      --parallel=*)
        DNSST_PARALLEL=${_opt#--parallel=}
        shift
        ;;
      --query-timeout)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_QUERY_TIMEOUT=$2
        shift 2
        ;;
      --query-timeout=*)
        DNSST_QUERY_TIMEOUT=${_opt#--query-timeout=}
        shift
        ;;
      --stats-interval)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_STATS_INTERVAL_RAW=$2
        shift 2
        ;;
      --stats-interval=*)
        DNSST_STATS_INTERVAL_RAW=${_opt#--stats-interval=}
        shift
        ;;
      --domain-count)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_DOMAIN_COUNT=$2
        shift 2
        ;;
      --domain-count=*)
        DNSST_DOMAIN_COUNT=${_opt#--domain-count=}
        shift
        ;;
      --domain-file)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_DOMAIN_FILE=$2
        shift 2
        ;;
      --domain-file=*)
        DNSST_DOMAIN_FILE=${_opt#--domain-file=}
        shift
        ;;
      --resolver-file)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_RESOLVER_FILE=$2
        shift 2
        ;;
      --resolver-file=*)
        DNSST_RESOLVER_FILE=${_opt#--resolver-file=}
        shift
        ;;
      --refresh-domains)
        DNSST_REFRESH_DOMAINS=1
        shift
        ;;
      --output-dir)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_OUTPUT_DIR=$2
        shift 2
        ;;
      --output-dir=*)
        DNSST_OUTPUT_DIR=${_opt#--output-dir=}
        shift
        ;;
      --query-type)
        dnsst_cli_need_arg "$_opt" "${2:-}"
        DNSST_QUERY_TYPE=$2
        shift 2
        ;;
      --query-type=*)
        DNSST_QUERY_TYPE=${_opt#--query-type=}
        shift
        ;;
      --include-disabled)
        DNSST_INCLUDE_DISABLED=1
        shift
        ;;
      --no-probe)
        DNSST_NO_PROBE=1
        shift
        ;;
      --list-resolvers)
        DNSST_LIST_RESOLVERS=1
        shift
        ;;
      --yes|-y)
        DNSST_YES=1
        shift
        ;;
      --no-install)
        DNSST_NO_INSTALL=1
        shift
        ;;
      --quiet|-q)
        DNSST_QUIET=1
        shift
        ;;
      --help|-h)
        dnsst_usage
        exit 0
        ;;
      --version|-V)
        printf 'dns-speedtest %s\n' "$DNSST_VERSION"
        printf 'Copyright (c) 2026 %s\n' "$DNSST_AUTHOR"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        dnsst_die "unknown option: $_opt (try --help)"
        ;;
      *)
        dnsst_die "unexpected argument: $_opt (try --help)"
        ;;
    esac
  done
  if [ $# -gt 0 ]; then
    dnsst_die "unexpected argument: $1 (try --help)"
  fi
  dnsst_validate_args
}

dnsst_validate_args() {
  if [ -n "$DNSST_DURATION_RAW" ]; then
    DNSST_DURATION_SECS=$(dnsst_parse_duration "$DNSST_DURATION_RAW") || \
      dnsst_die "invalid --duration '$DNSST_DURATION_RAW' (use 30s, 5m, 1h, or a positive number of seconds)"
  else
    DNSST_DURATION_SECS=0
  fi

  if ! dnsst_is_uint "$DNSST_PARALLEL" || [ "$DNSST_PARALLEL" -lt 1 ]; then
    dnsst_die "invalid --parallel '$DNSST_PARALLEL' (must be an integer >= 1)"
  fi

  if ! dnsst_is_uint "$DNSST_QUERY_TIMEOUT" || [ "$DNSST_QUERY_TIMEOUT" -lt 1 ]; then
    dnsst_die "invalid --query-timeout '$DNSST_QUERY_TIMEOUT' (must be an integer >= 1)"
  fi

  DNSST_STATS_INTERVAL_SECS=$(dnsst_parse_duration "$DNSST_STATS_INTERVAL_RAW") || \
    dnsst_die "invalid --stats-interval '$DNSST_STATS_INTERVAL_RAW'"

  case $(dnsst_lc "$DNSST_DOMAIN_COUNT") in
    all)
      DNSST_DOMAIN_COUNT_ALL=1
      DNSST_DOMAIN_COUNT=0
      ;;
    *)
      if ! dnsst_is_uint "$DNSST_DOMAIN_COUNT" || [ "$DNSST_DOMAIN_COUNT" -lt 1 ]; then
        dnsst_die "invalid --domain-count '$DNSST_DOMAIN_COUNT' (positive integer or 'all')"
      fi
      ;;
  esac

  if [ -n "$DNSST_DOMAIN_FILE" ] && [ ! -f "$DNSST_DOMAIN_FILE" ]; then
    dnsst_die "domain file not found: $DNSST_DOMAIN_FILE"
  fi

  if [ -n "$DNSST_RESOLVER_FILE" ] && [ ! -f "$DNSST_RESOLVER_FILE" ]; then
    dnsst_die "resolver file not found: $DNSST_RESOLVER_FILE"
  fi

  _qt=$(printf '%s' "$DNSST_QUERY_TYPE" | tr '[:lower:]' '[:upper:]')
  case "$_qt" in
    *[!A-Z0-9]*)
      dnsst_die "invalid --query-type '$DNSST_QUERY_TYPE'"
      ;;
    '')
      dnsst_die "invalid --query-type (empty)"
      ;;
  esac
  DNSST_QUERY_TYPE=$_qt

  if [ "$DNSST_YES" -eq 1 ] && [ "$DNSST_NO_INSTALL" -eq 1 ]; then
    dnsst_die "--yes and --no-install cannot be used together"
  fi
}
