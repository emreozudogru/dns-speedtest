#!/bin/bash
# dns-speedtest — measure DNS query time of resolver IP addresses.
# Compatible with Bash 3.2 (macOS /bin/bash) and Linux Bash.
# Do not require a newer Homebrew Bash.

_dnsst_find_root() {
  _src=${BASH_SOURCE[0]}
  _dir=$(cd "$(dirname "$_src")" && pwd) || exit 1
  if [ -L "$_src" ]; then
    _link=$(readlink "$_src")
    case "$_link" in
      /*) _dir=$(cd "$(dirname "$_link")" && pwd) || exit 1 ;;
      *)  _dir=$(cd "$_dir/$(dirname "$_link")" && pwd) || exit 1 ;;
    esac
  fi
  printf '%s' "$_dir"
}

DNSST_ROOT=$(_dnsst_find_root)

# shellcheck source=lib/common.sh
. "$DNSST_ROOT/lib/common.sh"
# shellcheck source=lib/cli.sh
. "$DNSST_ROOT/lib/cli.sh"
# shellcheck source=lib/deps.sh
. "$DNSST_ROOT/lib/deps.sh"
# shellcheck source=lib/resolvers.sh
. "$DNSST_ROOT/lib/resolvers.sh"
# shellcheck source=lib/domains.sh
. "$DNSST_ROOT/lib/domains.sh"
# shellcheck source=lib/query.sh
. "$DNSST_ROOT/lib/query.sh"
# shellcheck source=lib/stats.sh
. "$DNSST_ROOT/lib/stats.sh"
# shellcheck source=lib/report.sh
. "$DNSST_ROOT/lib/report.sh"
# shellcheck source=lib/run.sh
. "$DNSST_ROOT/lib/run.sh"

dnsst_prepare_output_dir() {
  if [ -n "$DNSST_OUTPUT_DIR" ]; then
    DNSST_OUTDIR=$DNSST_OUTPUT_DIR
  else
    DNSST_OUTDIR="results/$(dnsst_stamp)"
  fi
  if ! mkdir -p "$DNSST_OUTDIR" 2>/dev/null; then
    dnsst_die "cannot create output directory: $DNSST_OUTDIR"
  fi
  if [ ! -w "$DNSST_OUTDIR" ]; then
    dnsst_die "output directory is not writable: $DNSST_OUTDIR"
  fi
  # Probe write access with a real file.
  if ! : > "$DNSST_OUTDIR/.write-test" 2>/dev/null; then
    dnsst_die "output directory is not writable: $DNSST_OUTDIR"
  fi
  rm -f "$DNSST_OUTDIR/.write-test"
}

dnsst_main() {
  dnsst_parse_args "$@"

  if [ -z "$DNSST_RESOLVER_FILE" ]; then
    DNSST_RESOLVER_FILE=$(dnsst_resolver_file_default)
  fi
  DNSST_RESOLVER_FILE_USED=$DNSST_RESOLVER_FILE

  dnsst_parse_resolvers "$DNSST_RESOLVER_FILE" "$DNSST_INCLUDE_DISABLED"
  dnsst_select_resolvers

  if [ "$DNSST_LIST_RESOLVERS" -eq 1 ]; then
    dnsst_print_resolvers
    exit 0
  fi

  _need_dl=0
  if [ -z "$DNSST_DOMAIN_FILE" ]; then
    _need_dl=1
  fi
  dnsst_check_dependencies "$_need_dl"

  dnsst_prepare_domains
  dnsst_prepare_output_dir

  DNSST_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/dnsst.XXXXXX") || \
    dnsst_die "cannot create a temporary directory"
  dnsst_mkdir_p "$DNSST_WORKDIR/q"
  dnsst_stats_init
  dnsst_results_init

  trap dnsst_cleanup EXIT
  trap dnsst_on_signal INT TERM

  dnsst_run_benchmark

  if [ "$DNSST_INTERRUPTED" -eq 1 ]; then
    exit 130
  fi
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  dnsst_main "$@"
fi
