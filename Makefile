.DEFAULT_GOAL := help

.PHONY: help install sync test check ci eval coding-eval

help:
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Targets:' \
		"  install  Install this repository's agent configuration" \
		'  sync     Fast-forward and reinstall configuration' \
		'  test     Run the isolated behavioral tests' \
		'  check    Run checks against the current working tree' \
		'  ci       Run the same complete pipeline as GitHub Actions' \
		'  eval     Run paid skill evaluations with Claude Code (EVAL_ARGS=...)' \
		'  coding-eval  Describe coding trials; execution requires --execute (CODING_EVAL_ARGS=...)'

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

eval:
	python3 ./scripts/run-evals.py $(EVAL_ARGS)

coding-eval:
	python3 ./scripts/run-coding-evals.py $(CODING_EVAL_ARGS)
