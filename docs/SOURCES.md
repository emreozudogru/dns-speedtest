# External sources

Resolver IP addresses and the default domain ranking were taken from
official or primary project documentation on **2026-08-16**. They are
not copied from memory or from unofficial “public DNS lists”.

## Domain ranking

| Item | Value |
|---|---|
| Dataset | Tranco daily standard list (top 1 million registered domains) |
| Why | Alexa Top Sites is retired. Tranco is a maintained, research-oriented ranking with a public unauthenticated download and citable daily snapshots. |
| Permanent URL | https://tranco-list.eu/top-1m.csv.zip |
| Observed redirect | `307` → `/download/daily/top-1m.csv.zip` |
| Project page | https://tranco-list.eu/ |
| Format | ZIP containing a CSV of `rank,domain` (same shape as the old Alexa list) |
| Update cadence | Daily, by 00:00 UTC (Last-Modified on the object) |

Verified with an HTTP HEAD of the permanent URL on 2026-08-16 (HTTP 200,
`content-type: application/zip`, ~9.3 MiB).

## Public resolvers

| Provider | Addresses used in `config/resolvers.tsv` | Official source |
|---|---|---|
| Cloudflare 1.1.1.1 | `1.1.1.1`, `1.0.0.1` unfiltered; `1.1.1.2`/`1.0.0.2` malware; `1.1.1.3`/`1.0.0.3` family; IPv6 `2606:4700:4700::1111` | https://developers.cloudflare.com/1.1.1.1/ip-addresses/ |
| Google Public DNS | `8.8.8.8`, `8.8.4.4`; IPv6 `2001:4860:4860::8888` | https://developers.google.com/speed/public-dns/docs/using |
| Quad9 | `9.9.9.9` / `149.112.112.112` (blocklist); `9.9.9.10` (no blocklist); `9.9.9.11` (blocklist + ECS) | https://quad9.net/service/service-addresses-and-features/ |
| Cisco OpenDNS | `208.67.222.222` / `208.67.220.220` (Home); `208.67.222.123` / `208.67.220.123` (FamilyShield) | https://www.opendns.com/setupguide/ |
| AdGuard Public DNS | `94.140.14.140` / `94.140.14.141` (non-filtering); `94.140.14.14` (ads); `94.140.14.15` (family) | https://adguard-dns.io/en/public-dns.html |

Cloudflare’s own docs describe `1.1.1.1` as providing “fast, private DNS
lookups with no content filtering.” Quad9’s default `9.9.9.9` **does**
apply a malware/phishing blocklist. OpenDNS Home includes phishing
protection. Those behaviors are recorded in the TSV `filtering` column
and must not be treated as equivalent service types.

## `dig` timeout controls

From ISC BIND 9 `dig` (and confirmed on macOS system BIND 9.10.6):

| Flag | Meaning | Default |
|---|---|---|
| `+time=T` / `+timeout=T` | Per-attempt timeout in seconds (minimum 1) | 5 |
| `+tries=T` | Total UDP/TCP attempts | 3 |
| `+retry=T` | Retries after the first attempt | 2 |

`+timeout` is documented on current BIND; macOS 9.10.6 advertises `+time`
only. This tool uses `+time` for portability.

References:

- https://bind9.readthedocs.io/en/v9.18.28/manpages.html#dig-dns-lookup-utility
- local `dig -h` on macOS BIND 9.10.6

## Package names for `dig`

| Platform | Package | Evidence |
|---|---|---|
| Debian / Ubuntu | `bind9-dnsutils` (`dnsutils` is a transitional package) | https://packages.debian.org/sid/bind9-dnsutils |
| Fedora / RHEL-family | `bind-utils` | distribution package naming |
| Arch Linux | `bind` | Arch extra/`bind` |
| Alpine Linux | `bind-tools` | https://pkgs.alpinelinux.org/package/edge/main/x86/bind-tools |
| macOS Homebrew | `bind` | Homebrew formula `bind` |
| macOS system | `/usr/bin/dig` ships with the OS / Command Line Tools | local inspection |

Do not install Homebrew automatically if it is missing.
