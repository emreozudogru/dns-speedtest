# Contributing

Thanks for helping improve dns-speedtest. All project text, comments,
commit messages, and documentation are written in **English**.

## Development

- Target **Bash 3.2** (macOS `/bin/bash`) as well as Linux Bash.
- Do not use Bash 4+ features (associative arrays, `mapfile`, `wait -n`,
  `${var,,}`, and similar).
- Do not add Python, Node, `jq`, Perl, or GNU-only tools as runtime
  dependencies.
- Resolver files are data. Never `eval` or source user input.

## Checks

Run these before opening a pull request:

```bash
bash -n dns-speedtest.sh
bash -n lib/*.sh tests/run-tests.sh
./tests/run-tests.sh
shellcheck -x dns-speedtest.sh lib/*.sh tests/run-tests.sh
```

The automated suite must stay offline. Do not make unit tests depend on
public DNS.

## Pull requests

1. Open one pull request per change.
2. Keep the diff as small as possible.
3. Update `README.md` if you change CLI flags or default behavior.
4. Update `docs/SOURCES.md` if you add or change resolver addresses.
5. Use an English commit message that says *why*, not only *what*.

## Code of conduct

By participating you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
