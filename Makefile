.DEFAULT_GOAL := help

.PHONY: help install uninstall sync test check ci eval coding-eval skills-outdated

help:
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Targets:' \
		"  install  Install this repository's agent configuration" \
		'  uninstall  Remove everything the installer added' \
		'  sync     Fast-forward and reinstall configuration' \
		'  test     Run the isolated behavioral tests' \
		'  check    Run checks against the current working tree' \
		'  ci       Run the same complete pipeline as GitHub Actions' \
		'  eval     Run paid skill evaluations with Claude Code (EVAL_ARGS=...)' \
		'  coding-eval  Describe coding trials; execution requires --execute (CODING_EVAL_ARGS=...)' \
		'  skills-outdated  Check imported skill pins against upstream GitHub (needs gh)'

install:
	./install.sh

uninstall:
	./install.sh --uninstall

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

skills-outdated:
	python3 ./scripts/check-skill-upstreams.py
