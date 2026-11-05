# Contributing

Bug reports and pull requests are welcome. For a bug, the issue form asks
for the installed commit and your tmux and bash versions; a debug log
(`set -g @whichkey-debug on`, reload, reproduce, then
`~/.cache/whichkey-tmux/debug.log`) helps most.

## Setup

You need tmux 3.4+, bash, Python 3 (for the e2e test's pseudo-terminals),
[shellcheck](https://www.shellcheck.net) and [shfmt](https://github.com/mvdan/sh).

```sh
make lint   # shellcheck and shfmt -d
make fmt    # shfmt -w
make test   # tests/unit.sh and tests/e2e.sh
```

CI runs the same on Linux with every tmux release from 3.4, and on macOS
with the system bash 3.2.

## Before you change something

- [AGENTS.md](AGENTS.md): the rules (bash 3.2, `printf -v` helpers,
  quoting layers, how to read bindings) and the definition of done. Written
  for AI agents, and just as useful for people.
- [docs/architecture.md](docs/architecture.md): how it fits together.
- [docs/decisions.md](docs/decisions.md): why, and what was rejected.
- [docs/tmux-compatibility.md](docs/tmux-compatibility.md): what differs
  between tmux versions.
- [docs/testing.md](docs/testing.md): unit and e2e tests, CI, reading a CI
  failure, the demo recording.
