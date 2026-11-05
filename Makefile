SHELL_FILES := whichkey.tmux $(wildcard scripts/*.sh scripts/lib/*.sh tests/*.sh)

.PHONY: check lint fmt test unit e2e

check: lint test

lint:
	shellcheck $(SHELL_FILES)
	shfmt -d $(SHELL_FILES)

fmt:
	shfmt -w $(SHELL_FILES)

test: unit e2e

unit:
	bash tests/unit.sh

e2e:
	bash tests/e2e.sh
