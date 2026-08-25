.DEFAULT_GOAL := help

.PHONY: help install sync test check

help:
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Targets:' \
		"  install  Install this repository's agent configuration" \
		'  sync     Verify, fast-forward, and reinstall configuration' \
		'  test     Run the isolated behavioral tests' \
		'  check    Run all required repository checks'

install:
	./install.sh

sync:
	./sync.sh

test:
	./tests/run.sh

check:
	./scripts/check.sh
