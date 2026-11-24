# Install copies this bundle to <share>/bundles/roguelike, where `x -l` looks: a lang is
# installed when its files are there. No registry, no database.

X ?= x

# The version is derived from git describe, never committed: bundle.xon declares
# what this lang requires; the installed artifact carries what it is.
LANG_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/bundles/roguelike

# What a consumer needs to run the lang: the declaration, the entry, the
# modules, the data and the art.  Not the suite, not the tooling, not CI.
PAYLOAD := bundle.xon lib data art

# A bundle this one requires and the tree does not hold is installed from the
# release its row in bundle.xon names: "NAME" "VERSION" "OWNER/REPO" is that
# repository's published bundle.pin.xon, which `x --install-bundle` fetches
# and verifies.  A row with no repository is jonruttan/x-NAME, as the bundle
# CI reads it; one with no version is the latest release.  A bundle is there
# when some bundle.xon under bundles/ declares its name, which is how `x -l`
# looks; its version is not compared here -- the boot does that.
.PHONY: requirements
requirements: ## Install the bundles bundle.xon requires that are missing
	@test -n "$(SHARE)" || { echo "x-roguelike: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-roguelike: no x tree at $(SHARE)" >&2; exit 1; }
	@awk -F'"' '/^\(requires-bundle /{print $$2, ($$4 ? $$4 : "-"), ($$6 ? $$6 : "jonruttan/x-" $$2)}' bundle.xon | \
	while read -r name version repo; do \
		if grep -qsF "(name \"$$name\")" "$(SHARE)"/bundles/*/bundle.xon; then continue; fi; \
		if [ "$$version" = - ]; then rel=latest/download; else rel="download/$$version"; fi; \
		url="https://github.com/$$repo/releases/$$rel/bundle.pin.xon"; \
		echo "x-roguelike: requires $$name, which is not installed -- installing it"; \
		echo "\"$(X)\" --install-bundle $$url"; \
		"$(X)" --install-bundle "$$url" || { echo "x-roguelike: could not install $$name" >&2; exit 1; }; \
	done

.PHONY: install
install: requirements ## Install into <share>/bundles/roguelike, and what it requires
	@test -n "$(SHARE)" || { echo "x-roguelike: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-roguelike: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	printf '%s\n' '$(LANG_VERSION)' > "$(DEST)/version"
	@echo "x-roguelike: installed to $(DEST)"
	@echo "x-roguelike: writing the boot image"
	"$(X)" --image -l roguelike
	@echo "x-roguelike: try  x -l roguelike"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-roguelike: removed $(DEST)"

.PHONY: test
test: ## Run the spec suite (every failure is loud)
	X="$(X)" sh tests/spec-runner.sh

.PHONY: check
check: check-doc-folds ## Run the suite against tests/contract/known-failures.txt -- what CI gates on
	X="$(X)" sh tests/spec-gate.sh

.PHONY: check-doc-folds
check-doc-folds: ## Assert every section of docs/delve.md is folded shut
	sh tests/doc-folds.sh

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
