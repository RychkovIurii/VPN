SHELL := /usr/bin/env
.SHELLFLAGS := bash -eu -o pipefail -c

.DEFAULT_GOAL := help

.PHONY: help cli panel cli-% panel-%

help:
	@echo "Select environment:"
	@echo "  make cli         # list CLI-only targets"
	@echo "  make cli-<cmd>   # run target inside deployments/cli"
	@echo "  make panel       # list panel-enabled targets"
	@echo "  make panel-<cmd> # run target inside deployments/panel"

cli:
	@$(MAKE) -C deployments/cli help

panel:
	@$(MAKE) -C deployments/panel help

cli-%:
	@$(MAKE) -C deployments/cli $*

panel-%:
	@$(MAKE) -C deployments/panel $*
