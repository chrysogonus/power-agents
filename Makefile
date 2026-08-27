.DEFAULT_GOAL := help

.PHONY: help install sync test check ci

help:
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Targets:' \
		"  install  Install this repository's agent configuration" \
		'  sync     Verify, fast-forward, and reinstall configuration' \
		'  test     Run the isolated behavioral tests' \
		'  check    Run checks against the current working tree' \
		'  ci       Run the same complete pipeline as GitHub Actions'

install:
	./install.sh

sync:
	./sync.sh

test:
	./tests/run.sh

check:
	./scripts/check.sh

ci:
	./scripts/ci.sh
