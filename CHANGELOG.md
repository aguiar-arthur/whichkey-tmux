# Changelog

All notable changes are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.0] - 2026-11-04

First release.

### Added

- Catalog menu of a key table's bindings on `prefix Space`, built from
  `tmux list-keys`: your bindings first, tmux's defaults after, `+groups`
  as submenus, paginated when taller than the client.
- Auto mode (`@whichkey-auto`): a popup of your bindings after a pause on
  `prefix` or `prefix2`, and on group keys. Every key is forwarded to
  tmux, including function keys, modifier combinations and UTF-8
  characters, and typing at full speed never shows the popup.
- Works with several clients attached: a prefix on one does not cancel a
  popup pending on another.
- Options for the keys, delay, exclusions, label width, position, popup
  styles (`@whichkey-key-style`, `@whichkey-group-style`) and border.
- `@whichkey-debug` traces every run into a log file.
- Tested in CI on Linux with tmux 3.4, 3.5a, 3.6b, 3.7c and 3.8, and on
  macOS with the system bash 3.2.

[Unreleased]: https://github.com/aguiar-arthur/whichkey-tmux/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aguiar-arthur/whichkey-tmux/releases/tag/v0.1.0
