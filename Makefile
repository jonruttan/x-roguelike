# Install is the bundle tool's: `x -l bundle -- install .` copies what
# bundle.xon declares -- the declaration, lib/ and its (payload ...) rows --
# to <share>/bundles/roguelike, where `x -l` looks, and installs the bundles
# it requires.  This file only says where, and writes the boot image after.

X ?= x

SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/bundles/roguelike

# Where the bundle tool comes from on a tree that has none: its latest
# release's pin, which the platform's own `x --install-bundle` fetches and
# verifies.  The tool is there when some bundle.xon under bundles/ declares
# the name bundle, which is how `x -l` looks.
BUNDLE_PIN ?= https://github.com/jonruttan/x-bundle/releases/latest/download/bundle.pin.xon

.PHONY: install
install: ## Install into <share>/bundles/roguelike, with the bundles it requires
	@test -n "$(SHARE)" || { echo "x-roguelike: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-roguelike: no x tree at $(SHARE)" >&2; exit 1; }
	@grep -qsF '(name "bundle")' "$(SHARE)"/bundles/*/bundle.xon || { \
		echo "x-roguelike: no bundle tool in $(SHARE)/bundles -- installing it"; \
		echo '"$(X)" --install-bundle $(BUNDLE_PIN)'; \
		"$(X)" --install-bundle "$(BUNDLE_PIN)"; }
	"$(X)" -l bundle -- install . --dir "$(SHARE)/bundles"
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
