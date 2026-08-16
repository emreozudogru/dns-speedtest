# dns-speedtest

A command-line DNS resolver speed test written in portable Bash.

It measures the **DNS query time** of resolver IP addresses against a
representative list of popular domains. The clock that matters is the
`Query time: N msec` value reported by `dig`, not shell runtime, not
`curl`, and not ping.

```text
./dns-speedtest.sh --duration 5m
```

## Why this exists

Public DNS resolvers are often compared using anecdotes or a handful of
lookups. Those tests are easy to bias: one resolver is warmed, another is
cold, or every domain is sent to resolver A before resolver B ever sees
the workload.

This tool:

- queries **resolver IP addresses directly** (`dig @1.1.1.1 example.com A`)
- walks the workload **domain-first**, so every resolver sees the same
  names under similar network conditions
- records raw per-query data and a transparent ranking
- runs on **Linux** and **macOS system `/bin/bash` 3.2** (no Homebrew Bash)

Results describe **your** path to anycast resolvers at the time of the
run. They are not a universal ranking of “the fastest DNS on the
Internet.”

## Supported platforms

- Linux (Debian/Ubuntu, Fedora/RHEL-family, Arch, Alpine, and similar)
- macOS, including the system interpreter `/bin/bash` 3.2
- Requires `dig` (BIND). `curl` and `unzip` are required only when the
  Tranco list is downloaded (not when you pass `--domain-file`)

Do **not** install a newer Bash just to run this tool.

## Quick start

```bash
git clone <this-repo> dns-speedtest
cd dns-speedtest
chmod +x dns-speedtest.sh
./dns-speedtest.sh --duration 5m
```

The first run without `--domain-file` downloads the Tranco top-1M list
into `~/.cache/dns-speedtest/` and then tests the first 1000 names
against the enabled resolvers in `config/resolvers.tsv`.

## Examples

```bash
# Default: 1000 Tranco domains, sequential, bundled resolvers
./dns-speedtest.sh

# Five-minute test (soft deadline; the in-flight domain finishes)
./dns-speedtest.sh --duration 5m

# Same budget, up to 4 concurrent resolver queries per domain
./dns-speedtest.sh --duration 5m --parallel 4

# Larger sample
./dns-speedtest.sh --domain-count 10000

# Custom resolvers
./dns-speedtest.sh --resolver-file my-resolvers.tsv

# Custom domains (one name per line)
./dns-speedtest.sh --domain-file domains.txt

# Consume an entire custom domain file
./dns-speedtest.sh --domain-file domains.txt --domain-count all

# Force a fresh Tranco download
./dns-speedtest.sh --refresh-domains

# Non-interactive install of a missing package (e.g. dig)
./dns-speedtest.sh --yes

# Never attempt to install anything
./dns-speedtest.sh --no-install

# Show the parsed resolver database
./dns-speedtest.sh --list-resolvers
```

## CLI

| Option | Default | Meaning |
|---|---|---|
| `--duration DUR` | *(full list)* | Soft global budget: `30s`, `5m`, `1h`, or a second count |
| `--parallel N` | `1` | Concurrent resolver queries **within one domain** |
| `--query-timeout SEC` | `2` | `dig +time=SEC +tries=1 +retry=0` |
| `--stats-interval DUR` | `5s` | Live progress cadence |
| `--domain-count N` | `1000` | First N valid domains; `all` disables the cap |
| `--domain-file FILE` | Tranco | User domain list |
| `--resolver-file FILE` | `config/resolvers.tsv` | User resolver TSV |
| `--refresh-domains` | off | Re-download Tranco even if a cache exists |
| `--output-dir DIR` | `results/YYYYMMDD-HHMMSS` | Result directory |
| `--query-type TYPE` | `A` | Record type passed to `dig` |
| `--include-disabled` | off | Also test TSV rows marked disabled |
| `--list-resolvers` | — | Print the parsed resolver list and exit |
| `--yes`, `-y` | off | Auto-approve installing a missing package |
| `--no-install` | off | Never install packages |
| `--quiet`, `-q` | off | No live progress (final table still prints) |
| `--help`, `-h` | — | Help |
| `--version`, `-V` | — | Version |

Invalid values (`--duration banana`, `--parallel 0`, a missing file, a
malformed resolver TSV) fail immediately with an actionable message.

## Dependencies

At startup the tool checks the commands this run actually needs.

Always required: `bash`, `dig`, `awk`, `sed`, `grep`, `sort`, `mktemp`,
`date`, and the usual POSIX file utilities.

Only when downloading Tranco: `curl`, `unzip`.

There is **no** runtime dependency on Python, Node, `jq`, Perl, or GNU
coreutils. GNU `timeout` / `gdate` / `gsed` are not used.

### If `dig` (or another required tool) is missing

The program:

1. Identifies the OS
2. Detects a package manager that is **already installed**
3. Names the correct package
4. Asks before installing anything

```text
dig was not found.
Detected platform: Ubuntu 24.04 LTS
Package manager: apt
Required package: bind9-dnsutils
Install it now? [y/N]
```

| Platform | `dig` package |
|---|---|
| Debian / Ubuntu | `bind9-dnsutils` |
| Fedora / RHEL-family | `bind-utils` |
| Arch Linux | `bind` |
| Alpine Linux | `bind-tools` |
| macOS + Homebrew | `bind` |

`--yes` answers the prompt. `--no-install` never installs.

This tool will **not** install Homebrew. If macOS has neither `dig` nor
Homebrew, it explains how to install Xcode Command Line Tools
(`xcode-select --install`) or Homebrew yourself, then exits.

## Domain source

Alexa Top Sites is retired and is not used.

The default list is the **Tranco** daily top-1 million ranking:

- Project: <https://tranco-list.eu/>
- Permanent URL: <https://tranco-list.eu/top-1m.csv.zip>
  (redirects to the current daily zip; verified 2026-08-16)
- Format: `rank,domain`

Tranco is a maintained research ranking with a public, unauthenticated
download. That is why it is the default. Citations and the verification
notes live in [`docs/SOURCES.md`](docs/SOURCES.md).

### Cache

Downloads land in `${XDG_CACHE_HOME:-$HOME/.cache}/dns-speedtest/`.

- First use downloads the zip, extracts it to a temp file, validates it,
  then atomically renames it into the cache.
- Later runs reuse the cache.
- `--refresh-domains` forces a new download.
- A failed download with a valid cache prints a warning and continues.
- A failed download with no cache exits and tells you to pass
  `--domain-file`.

### `--domain-count` and `--domain-file`

`--domain-count` always means “use the first N **valid** names after
comments and blank lines are stripped.”

It applies to **both** Tranco and `--domain-file`. If the file has fewer
than N names, every valid name is used. `--domain-count all` disables
the cap.

Default `1000` is large enough for a stable median and p95 and small
enough for a sequential run of a handful of resolvers.

Custom files: one domain per line, `#` comments, blank lines, and CRLF
are accepted. Ranked `N,domain` lines (Tranco/Alexa style) are accepted.
Names are validated; they are never `eval`’d.

## Resolver database

Default file: [`config/resolvers.tsv`](config/resolvers.tsv).

Tab-separated columns:

```text
enabled  provider  ip  service_type  filtering  notes  source
```

- `enabled`: `1`/`0`, `yes`/`no`, `true`/`false`
- `ip`: IPv4 or IPv6 (hostnames are rejected — this tool benchmarks
  addresses, not names)
- `#` comments and blank lines are allowed
- A malformed row **aborts** with `file:line` (nothing is skipped silently)

The file is parsed as data. It is never sourced as Bash.

### Default enabled resolvers

Verified against official documentation on 2026-08-16
(see [`docs/SOURCES.md`](docs/SOURCES.md)):

| Provider | IP | Filtering |
|---|---|---|
| Cloudflare | `1.1.1.1` / `1.0.0.1` | none (standard 1.1.1.1) |
| Cloudflare | `1.1.1.2` / `1.0.0.2` | malware (1.1.1.1 for Families) |
| Cloudflare | `1.1.1.3` / `1.0.0.3` | family (malware + adult content) |
| Google | `8.8.8.8` / `8.8.4.4` | none |
| Quad9 | `9.9.9.9` / `149.112.112.112` | malware / phishing blocklist (Quad9 default) |
| OpenDNS | `208.67.222.222` / `208.67.220.220` | phishing protection (OpenDNS Home) |
| AdGuard | `94.140.14.140` / `94.140.14.141` | none (official non-filtering server) |
| TurkNet | `193.192.98.8` / `212.154.100.18` | none (ISP recursive DNS) |
| Control D | `76.76.2.0` / `76.76.10.0` | none (free unfiltered) |
| CIRA | `149.112.121.10` / `149.112.122.10` | none (Canadian Shield Private) |
| CleanBrowsing | `185.228.168.9` / `185.228.169.9` | malware (Security Filter) |
| DNS4EU | `86.54.11.100` / `86.54.11.200` | none (Unfiltered) |
| Yandex | `77.88.8.8` / `77.88.8.1` | none (Basic) |

Official IPv4 secondaries of enabled services are **on**. IPv6 rows and
extra filtering products (Quad9 unsecured/ECS, OpenDNS FamilyShield,
AdGuard ads/family, Control D malware/family, CIRA Protected/Family,
CleanBrowsing Family/Adult, DNS4EU Protective/Child, Yandex Safe/Family)
ship **disabled** and labeled. Enable them in the TSV or pass
`--include-disabled`. Do not treat a filtering resolver as equivalent to
an unfiltered one.

Mullvad’s published IPs are **DoH/DoT only** (not UDP/53) and are not
included. dns0.eu has been discontinued. Hurricane Electric has no
official public-resolver product page, so it is omitted.

## How queries are made

```text
HOME=$workdir dig +time=2 +tries=1 +retry=0 +nosearch +ignore \
    +nocmd +noquestion +noauthority +noadditional \
    +comments +stats +answer \
    @RESOLVER_IP domain A
```

- Queries go to the configured **IP**, never to a resolver hostname.
- Default type is `A`. DoH and DoT are out of scope.
- `+time` / `+tries` / `+retry` are the portable BIND controls (macOS
  BIND 9.10.6 advertises `+time`, not the newer `+timeout` alias).
- Default: **one attempt, 2 seconds**. BIND’s own default (5s × 3 tries)
  would stall a benchmark on a dead resolver.
- `+ignore` prevents a TC=1 UDP answer from being retried over TCP
  (that extra RTT is not “the DNS query time” we want).
- `HOME` is pointed at the work directory so `~/.digrc` cannot change
  flags. (macOS `dig` 9.10.6 has no portable `-r`.)

The recorded latency is the `Query time: N msec` line. If `dig` does not
print one, the field is left empty. It is **never** invented and never
stored as `0` for a timeout.

## Test ordering (domain-first)

```text
domain1 → resolver1, resolver2, resolver3, …
domain2 → resolver1, resolver2, resolver3, …
domain3 → …
```

Not the other way around. All resolvers see approximately the same names
under similar temporal and network conditions.

## Sequential vs parallel

Default `--parallel 1` is sequential and is the fairest latency
comparison.

`--parallel N` may run up to N resolver queries for the **current
domain** at once. The next domain does not start until every selected
resolver has finished the current one.

Parallelism is implemented with ordinary background jobs and `wait`
(no Bash 4 `wait -n`).

**Concurrency itself changes latency.** Shared uplink, NAT, and resolver
rate limits can make a parallel run look different from a sequential
one. Use `--parallel 1` when you care about the cleanest comparison;
use `--parallel 4` when you want wall-clock time back.

## Duration semantics

`--duration` is a **soft global budget**.

- A new **domain round** starts only if the budget has not expired.
- Once a domain has started, it is finished against **every** selected
  resolver (including in-flight parallel queries).
- Active `dig` processes are **not** killed because the budget expired.
- Wall-clock runtime may therefore slightly exceed `--duration`.
- That is intentional: it keeps the last domain a fair comparison.

SIGINT / SIGTERM (Ctrl+C) is different: in-flight children are
terminated, partial results are written, and the run is marked
`interrupted` (exit 130).

## Statistics

Per resolver:

| Metric | Definition |
|---|---|
| Queries | Attempts |
| Success | DNS response with RCODE `NOERROR` or `NXDOMAIN` **and** a `Query time` |
| Failed | Everything else |
| Timeouts | No response (`timed out` / `no servers could be reached`) |
| Success rate | Success / Queries |
| Min / Max / Mean | From successful query times only |
| Median | Middle sample; mean of the two central samples when *n* is even |
| P95 / P99 | Nearest-rank: `ceil(p/100 × n)` on the sorted successful times |

`NXDOMAIN` counts as success for **resolver reliability**: the resolver
answered correctly that the name does not exist. `SERVFAIL` and
`REFUSED` are failures. Timeouts are failures and are **never** entered
as `0 ms`.

NOERROR with zero answers (NODATA) is success if `Query time` is
present. CNAME chains that end in a normal answer are success.

## Ranking

There is no opaque score.

1. A resolver is **UNRELIABLE** if success rate `< 95%`, or
   **INSUFFICIENT** if it has fewer than 5 successful samples.
2. Reliable resolvers rank above flagged ones.
3. Within a group: lower median, then lower p95, then lower mean, then
   higher success rate.

The 95% / 5-sample rule exists so a resolver that answers once in 5 ms
and times out otherwise cannot win. Raw numbers are always printed.

## Live display

Every `--stats-interval` (default 5s) the tool reports elapsed time,
the configured budget, the current domain, domains/queries completed,
and per-resolver counts, success rate, running average / median / p95,
last query time, and timeouts.

On a TTY the block is rewritten in place. When stdout is not a terminal
(or `--quiet` is set) it falls back to plain log lines or silence. No
TUI library is used.

## Output files

Default directory: `results/YYYYMMDD-HHMMSS/`
(`--output-dir` uses the path you give, as-is).

| File | Contents |
|---|---|
| `queries.csv` | One row per query (timestamp, domain, provider, IP, type, RCODE, outcome, success, query time, answers, error, filtering) |
| `summary.csv` | One row per resolver with every aggregate metric |
| `summary.json` | The same summary as valid JSON (no `jq`) |
| `metadata.txt` / `metadata.json` | Version, times, OS, Bash, files used, counts, timeouts, parallelism, duration, stop reason, cache info |

CSV follows RFC 4180 quoting. JSON strings are escaped by the tool
itself.

## Methodology caveats

DNS query time is sensitive to:

- your geographic location and ISP routing
- resolver anycast routing (the instance you hit)
- network load and packet loss
- resolver cache state (cold vs warm)
- local Wi-Fi / NAT / CPE
- query concurrency (`--parallel`)

A laptop in one city and a VPS in another will not agree. Re-run from
the network you actually care about. Compare resolvers from the **same**
run; do not splice medians from different evenings.

Filtering resolvers will `NXDOMAIN` (or rewrite) names that unfiltered
resolvers answer. That is a behavior difference, not proof they are
“slower” or “broken.”

## Troubleshooting

| Symptom | What to try |
|---|---|
| `dig was not found` | Accept the install prompt, or install the package in the table above |
| Tranco download fails | Use `--domain-file`, or inspect `~/.cache/dns-speedtest/` |
| Every resolver times out | Check UDP/53 egress; try `--query-timeout 5` |
| One resolver is all timeouts | It may be blocked on your network; that is a real result |
| Parallel looks worse than sequential | Expected; shared capacity. Use `--parallel 1` for latency |
| IPv6 rows do nothing | The parser accepts them; enable them only if you have IPv6 |

## Tests and CI

```bash
./tests/run-tests.sh
```

The suite is offline: it uses mock `dig` / `curl` and fixture transcripts.
GitHub Actions runs syntax checks, ShellCheck, and the suite on Ubuntu
and on macOS `/bin/bash`.

## Limitations

- DoH / DoT / DoQ are not measured.
- Resolver hostnames are not benchmarked (by design).
- Only a single query type per run (default `A`).
- The bundled enabled set is IPv4. IPv6 works if you enable those rows
  and have IPv6 connectivity.
- Median / p95 during the live display are computed from files on each
  interval; they are correct but not free on huge runs.

## License

MIT. See [LICENSE](LICENSE).
