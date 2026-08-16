# Security policy

## Supported versions

Only the latest commit on `main` is supported.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use a private GitHub security advisory:

https://github.com/emreozudogru/dns-speedtest/security/advisories/new

Include:

- A description of the issue
- Steps to reproduce
- Affected version or commit
- Any suggested fix, if you have one

We will acknowledge the report and work on a fix before any public
disclosure.

## Scope notes

This tool runs local shell commands (`dig`, `curl`, package managers
only after consent). Treat resolver files and domain lists as untrusted
data. Do not `eval` user input in contributions.
