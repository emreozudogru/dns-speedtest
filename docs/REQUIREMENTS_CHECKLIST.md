# Requirements checklist

Verified against the repository on 2026-08-16. An item is marked
**done** only after the implementation (and, where practical, a test)
was inspected.

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Bash CLI DNS speed test; Linux + macOS `/bin/bash` 3.2; no Homebrew Bash; no Bash 4+ features | done | `#!/bin/bash`; CI macOS job uses `/bin/bash`; suite passed on 3.2.57; feature grep |
| 2 | `PLAN.md` written first, then implementation | done | `PLAN.md` |
| 3 | `dig @IP domain A`; extract `Query time`; record RCODE / timeout distinctly; no DoH/DoT | done | `lib/query.sh`; integration CSV shows `NOERROR` + msec from `dig` |
| 4 | Domain-first ordering | done | sequential + parallel tests; live `queries.csv` is domain then resolvers |
| 5 | `--parallel N`, default 1; domain-first; no `wait -n` | done | `lib/run.sh`; tests; README caveat |
| 6 | Soft `--duration`; finish in-flight domain; do not kill `dig` | done | duration test: 1 domain completed, all 3 resolvers, `stop_reason=duration` |
| 7 | `--query-timeout`; default 2s, one try | done | `+time=T +tries=1 +retry=0`; documented |
| 8 | External resolver TSV; official IPs; filtering labeled; IPv6 accepted | done | `config/resolvers.tsv`; `docs/SOURCES.md`; IPv6 parse test |
| 9 | `--resolver-file`; validate; comments/blanks; no silent skip | done | malformed-IP test; parser dies with file:line |
| 10 | Downloadable maintained domain list; not Alexa | done | Tranco permanent zip URL verified 2026-08-16 |
| 11 | Domain cache; `--refresh-domains`; atomic replace; cache fallback | done | `lib/domains.sh` |
| 12 | `--domain-file`; comments/blanks/CRLF; no `eval` | done | parser tests; `eval` audit |
| 13 | `--domain-count` default 1000; documented vs custom file | done | CLI + README |
| 14 | Detect required commands; no Python/jq/GNU-only at runtime | done | `lib/deps.sh` |
| 15 | Consented install; `--yes`; `--no-install`; no Homebrew auto-install | done | `lib/deps.sh` |
| 16 | Portable date/stat/sed/awk/mktemp; no GNU `timeout`/`gdate` | done | `date +%s`, `mktemp -d …XXXXXX` |
| 17 | Per-resolver stats including median/p95/p99; timeouts ≠ 0 ms | done | stats tests; timeout CSV test |
| 18 | Rank by reliability then median then p95; flag unreliable | done | ranking test |
| 19 | Live stats + `--stats-interval`; TTY vs log fallback | done | `lib/report.sh` |
| 20 | Final ranking table | done | integration run |
| 21 | CSV + JSON; raw + summary | done | `queries.csv`, `summary.csv`, `summary.json` validated |
| 22 | Run metadata | done | `metadata.txt` / `metadata.json` |
| 23 | Signal handling; duration ≠ interrupt; Ctrl+C writes partial results | done | `lib/run.sh` traps |
| 24 | Polished CLI; invalid args fail | done | CLI tests |
| 25 | Latency is `dig` query time only | done | classifier + integration times match `Query time` |
| 26 | Edge cases: timeout, SERVFAIL, REFUSED, NXDOMAIN, missing time, bad IP | done | fixtures + tests |
| 27 | No `eval`; quote; parse TSV as data; safe temps | done | audit + `mktemp -d` |
| 28 | Offline automated tests covering the required list | done | `tests/run-tests.sh` 92/92 |
| 29 | ShellCheck | done | ShellCheck 0.10.0 exit 0 on all scripts |
| 30 | GitHub Actions Ubuntu + macOS `/bin/bash` | done | `.github/workflows/ci.yml` |
| 31 | Professional README | done | `README.md` |
| 32 | README examples match CLI | done | compared to `lib/cli.sh` |
| 33 | Clean repo layout | done | see tree in PLAN/README |
| 34 | Full verification loop | done | syntax, ShellCheck, suite, integration |
| 35 | Small real integration test | done | 5 resolvers × 5 domains, 25/25 NOERROR |
| 36 | Current research for Tranco, IPs, packages, `dig` flags | done | `docs/SOURCES.md` |
| 37–38 | Measurement integrity, fair comparison, transparency | done | design in PLAN + README |
| 39 | This checklist | done | this file |

## Not verified in this environment

- GitHub Actions runners (workflow is present; not executed here).
- Package installation paths on Debian/Fedora/Arch/Alpine (logic reviewed; not executed).
- IPv6 query path against a live IPv6-only resolver (parser accepts IPv6; no live IPv6 query was run).
- SIGINT partial-result path was reviewed in code, not exercised by sending Ctrl+C.
