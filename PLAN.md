# Implementation Plan — dns-speedtest

Production-quality Bash DNS resolver benchmark. This document records architecture and the decisions that follow from the requirements. Implementation proceeds immediately after this file is written.

## 1. Architecture

Single user-facing executable `dns-speedtest.sh` (`#!/bin/bash`) plus small sourced libraries under `lib/`. Libraries exist so tests can exercise parsers, statistics, ranking, and CLI helpers without a live network.

```
dns-speedtest.sh          # CLI entry, orchestration
lib/common.sh             # logging, time, CSV/JSON, validation helpers
lib/cli.sh                # argument parsing and usage
lib/deps.sh               # required-command detection and consented install
lib/resolvers.sh          # TSV resolver database parser
lib/domains.sh            # Tranco download, cache, custom domain files
lib/query.sh              # dig invocation and output classification
lib/stats.sh              # per-resolver metrics and ranking
lib/report.sh             # live display, final table, result files
lib/run.sh                # domain-first sequential/parallel engine
config/resolvers.tsv      # default resolver database
docs/SOURCES.md           # official IP and dataset citations
tests/                    # offline test suite + fixtures + mocks
.github/workflows/ci.yml  # Ubuntu + macOS system Bash
```

The script resolves its own directory portably (no GNU `readlink -f`) and sources libraries from there. Resolver files are parsed as data, never sourced.

## 2. CLI design

| Option | Default | Meaning |
|---|---|---|
| `--duration DUR` | unset (full list) | Soft global budget: `Ns` / `Nm` / `Nh` or a bare second count |
| `--parallel N` | `1` | Max concurrent resolver queries **within one domain** |
| `--query-timeout SEC` | `2` | `dig +time=SEC +tries=1 +retry=0` |
| `--stats-interval DUR` | `5s` | Live progress cadence |
| `--domain-count N` | `1000` | First N valid domains (`all` = no cap) |
| `--domain-file FILE` | Tranco cache/download | User domain list |
| `--resolver-file FILE` | `config/resolvers.tsv` | User resolver TSV |
| `--refresh-domains` | off | Force re-download of Tranco |
| `--output-dir DIR` | `results/YYYYMMDD-HHMMSS` | Exact result directory |
| `--query-type TYPE` | `A` | Record type passed to `dig` |
| `--include-disabled` | off | Also test TSV rows marked disabled |
| `--list-resolvers` | — | Print parsed resolver DB and exit |
| `--yes` / `-y` | off | Auto-approve missing-package install |
| `--no-install` | off | Never attempt package installation |
| `--quiet` / `-q` | off | No live stats; still write files and final table |
| `--help` / `-h` | — | Help |
| `--version` / `-V` | — | Version |

Invalid values fail immediately with an actionable message. Unknown options fail. Short flags are limited (`-h -V -y -q`).

## 3. Resolver file format

Tab-separated, UTF-8, `#` comments, blank lines allowed, CRLF stripped.

```
enabled  provider  ip  service_type  filtering  notes  source
```

- `enabled`: `1`/`0`, `yes`/`no`, `true`/`false` (case-insensitive)
- `ip`: IPv4 or IPv6 (parser accepts IPv6; default enabled rows are IPv4)
- Remaining fields are metadata. They are never executed.
- Malformed rows abort with file:line context. Nothing is silently skipped.

Default enabled set is general-purpose public Do53 IPv4, one primary per major provider. Filtering variants and secondaries ship disabled and labeled.

## 4. Domain acquisition

**Source:** Tranco daily top-1M (Alexa is retired). Official permanent URL `https://tranco-list.eu/top-1m.csv.zip` (302 → `/download/daily/top-1m.csv.zip`) was verified on 2026-08-16. Format is `rank,domain`. No authentication.

**Why Tranco:** designed for reproducible research rankings; public unauthenticated download; still maintained; Alexa is gone.

**Cache:** `${XDG_CACHE_HOME:-$HOME/.cache}/dns-speedtest/tranco-top-1m.csv`

- Download to a temp file, unzip to a temp CSV, validate, then atomic `mv`.
- `--refresh-domains` forces a new download.
- Download failure + valid cache → warn and continue.
- Download failure + no cache → exit and recommend `--domain-file`.

**Custom `--domain-file`:** one domain per line, comments/blanks/CRLF supported. `--domain-count` still applies (first N valid names). Use `--domain-count all` to consume the whole file.

**Default count `1000`:** enough for stable median/p95, small enough for a sequential run of a handful of resolvers.

## 5. Timing model

Two independent clocks:

1. **Per-query DNS time** — only the `Query time: N msec` value from `dig`. Never wall-clock, never `curl`, never ping. If `dig` does not report a query time, the field is empty (not `0`).
2. **Global `--duration`** — soft wall-clock budget using portable `date +%s`.
   - Do not start a new **domain round** after the deadline.
   - Finish the in-flight domain against every selected resolver.
   - Do not kill an active `dig` because the budget expired.
   - Actual runtime may exceed `--duration`.

Per-query timeout is `dig +time=T +tries=1 +retry=0` (BIND: `+time` default 5s, `+tries` default 3). One 2-second attempt is the default so a dead resolver cannot stall a round. macOS BIND 9.10.6 exposes `+time`/`+tries`/`+retry`; `+timeout` is a newer alias and is not used.

`dig` is invoked with `@<ip>` only (never a resolver hostname), `+nosearch`, `+ignore` (no TCP fallback on TC=1), and a dummy `HOME` so `~/.digrc` cannot change measurement flags.

## 6. Statistics model

Classifications (mutually exclusive error types; a query is exactly one outcome):

| Outcome | Meaning | Counts as success? | Used in latency stats? |
|---|---|---|---|
| `success` | DNS response `NOERROR` or `NXDOMAIN` **and** `Query time` present | yes | yes |
| `nxdomain` | subset of success; recorded separately | yes | yes |
| `servfail` / `refused` / other RCODE | resolver answered with an error RCODE | no | no |
| `timeout` | no response (`timed out` / `no servers could be reached`) | no | **never** (not 0 ms) |
| `command_failure` | `dig` failed or output unparseable | no | no |

`NXDOMAIN` is success for **resolver reliability** (the resolver answered correctly). Latency uses only successful query times.

Computed per resolver from those successful times:

- attempted, successful, failed, timeouts, success rate
- min, max, arithmetic mean
- median (mean of two central samples when *n* is even)
- p95 / p99 (nearest-rank: `ceil(p/100 * n)`)

**Ranking (transparent, no opaque score):**

1. Flag `UNRELIABLE` if success rate `< 95%` **or** successful samples `< 5`.
2. Reliable resolvers rank above unreliable ones.
3. Within a group: lower median, then lower p95, then lower mean, then higher success rate.
4. Raw metrics are always printed; the user is never asked to trust a composite number.

## 7. Dependency management

Startup checks only the commands this run actually needs.

Always: `bash`, `awk`, `sed`, `grep`, `sort`, `mktemp`, `date`, `tr`, `cut`, `wc`, `uname`, `mkdir`, `mv`, `rm`, `cat`, `printf`, `head`, `tail`, `dig`.

If downloading Tranco (no `--domain-file`): also `curl` and `unzip`.

Missing **required** tool:

1. Identify OS (`uname` + `/etc/os-release`).
2. Identify a package manager already present (never install a package manager).
3. Name the package.
4. Ask `[y/N]` unless `--yes`. `--no-install` skips the prompt and exits.

| Platform | `dig` package | `curl` | `unzip` |
|---|---|---|---|
| Debian / Ubuntu | `bind9-dnsutils` | `curl` | `unzip` |
| Fedora / RHEL / CentOS | `bind-utils` | `curl` | `unzip` |
| Arch | `bind` | `curl` | `unzip` |
| Alpine | `bind-tools` | `curl` | `unzip` |
| macOS + Homebrew | `bind` | (system) | (system) |
| macOS, no Homebrew | explain how to install Xcode CLT / Homebrew; **do not** install Homebrew | | |

No Python / Node / jq / Perl / GNU coreutils at runtime.

## 8. Linux / macOS compatibility

Target: Linux Bash and macOS `/bin/bash` 3.2.

Forbidden: associative arrays, `mapfile`/`readarray`, `${var,,}`, `wait -n`, `nameref`, GNU `timeout`, GNU `date -d`, `readlink -f`, `gdate`/`gsed`.

Portable choices:

- Epoch seconds via `date +%s`; result stamp via `date +%Y%m%d-%H%M%S`
- `mktemp -d "${TMPDIR:-/tmp}/dnsst.XXXXXX"`
- Lowercase via `tr '[:upper:]' '[:lower:]'`
- Parallelism: launch a batch of at most `--parallel` background `dig`s for the **current domain**, `wait` each PID, then start the next batch. Next domain starts only after the whole resolver list for the current domain is done.
- Result collection via per-query temp files (no shared-variable writes from children).

## 9. Testing strategy

`tests/run-tests.sh` is a dependency-free Bash runner. Unit tests must not need the Internet.

Mocks: `tests/mocks/dig`, `tests/mocks/curl`, fixture `dig` transcripts (NOERROR, NXDOMAIN, SERVFAIL, REFUSED, timeout, missing query time).

Coverage required by the prompt:

- CLI / duration / resolver / domain parsing
- median, p95, p99, mean, min, max
- failures and timeouts excluded from latency
- ranking + unreliable flag
- soft duration deadline
- domain-first sequential **and** parallel order
- dependency detection
- CSV / JSON validity
- cleanup
- malformed arguments

A small real integration run (few resolvers × few domains) is performed manually in this environment when the network is available, and is **not** part of the default unit suite.

CI: GitHub Actions on `ubuntu-latest` and `macos-latest`, the latter invoking `/bin/bash` explicitly.

## 10. Failure handling

- One resolver failing does not stop the others.
- User SIGINT/SIGTERM: stop new work, terminate in-flight children, write partial results, mark `interrupted` in metadata, exit 130.
- Duration expiry: not an interrupt; finish the current domain; `stop_reason=duration`.
- Unwritable output dir / temp dir: fail clearly.
- Download / cache errors: see §4.
- No `eval`, no sourcing of user data, all expansions quoted.

## 11. Output formats

Directory (default `results/YYYYMMDD-HHMMSS/`):

- `queries.csv` — one row per query
- `summary.csv` — one row per resolver
- `summary.json` — same metrics, valid JSON, no `jq`
- `metadata.txt` / `metadata.json` — run context
- `query.log` — optional debug copy of classifications

CSV uses RFC 4180 quoting. JSON strings are escaped in portable `awk`.

Live display: TTY gets a compact periodically rewritten block; non-TTY / `--quiet` / missing terminal caps fall back to interval log lines or silence.

## 12. Default resolvers (enabled)

Verified 2026-08-16 against official docs (see `docs/SOURCES.md`):

- Cloudflare `1.1.1.1` — unfiltered
- Google `8.8.8.8` — unfiltered
- Quad9 `9.9.9.9` — malware/phishing blocklist (labeled)
- OpenDNS `208.67.222.222` — phishing protection (labeled)
- AdGuard `94.140.14.140` — official non-filtering server

Secondaries, IPv6 examples, and family/malware variants ship disabled.

## 13. Implementation order

1. Write this plan.
2. Scaffold repo files, resolver TSV, sources doc.
3. Implement libraries + main script.
4. Implement tests + CI + README.
5. Syntax check, ShellCheck, test suite, small live run.
6. Self-audit against the original requirements; fix gaps.

## 14. Open decisions (resolved here, not deferred)

- Executable name: `dns-speedtest.sh` (matches the request).
- Domain source: Tranco daily zip, not Cisco Umbrella or a static committed list.
- Reliability threshold: 95% success and at least 5 successful samples.
- Default parallelism: 1 (sequential) because concurrency itself changes latency.
- `dig` flags: `+time=2 +tries=1 +retry=0 +ignore +nosearch`; no DoH/DoT.
- `--domain-count` applies to both Tranco and `--domain-file`.

## 15. Implementation notes (post-build)

The implementation follows this plan. Extra CLI flags that earned their
keep: `--query-type`, `--include-disabled`, `--list-resolvers`.

ShellCheck is configured via `.shellcheckrc` (`shell=bash`). SC2034 is
disabled project-wide because globals are assigned in one module and
read in another; ShellCheck cannot see those uses when it lints a
single file.

Live progress: TTY stderr gets a rewritten per-resolver block; non-TTY
stderr gets a single elapsed/domains/queries/current line so redirected
runs are not flooded.

Verification (2026-08-16, macOS 13, `/bin/bash` 3.2.57):

- `bash -n` on every script
- ShellCheck 0.10.0 clean
- `tests/run-tests.sh`: 92 passed, 0 failed
- Live integration: 5 resolvers × 5 domains, 25/25 `NOERROR`, ranking
  and JSON/CSV inspected

