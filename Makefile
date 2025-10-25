# Mini-MWAN Build Orchestration
# Uses docker-compose to build packages with official Makefile structure

.PHONY: all build shell feeds-fetch feeds-register help
.DEFAULT_GOAL := all

# Full build: fetch feeds, register them, then build packages
all: feeds-fetch feeds-register build
	@echo ""
	@echo "=== Full build complete ==="

# Build both packages (uses official Makefile with luci.mk)
build:
	@echo "=== Building packages (official structure with luci.mk) ==="
	docker-compose run --rm openwrt-sdk bash -c "\
		mkdir -p /builder/package/feeds/packages/mini-mwan && \
		mkdir -p /builder/package/feeds/luci/luci-app-mini-mwan && \
		tar -cf - --exclude='Makefile.devcontainer' -C /builder/package/mini-mwan . | tar -xvf - -C /builder/package/feeds/packages/mini-mwan && \
		tar -cf - --exclude='Makefile.devcontainer' -C /builder/package/luci-app-mini-mwan . | tar -xvf - -C /builder/package/feeds/luci/luci-app-mini-mwan && \
		make defconfig && \
		make -j1 V=s package/feeds/packages/mini-mwan/compile && \
		make -j1 V=s package/feeds/luci/luci-app-mini-mwan/compile && \
		echo '' && \
		echo '=== Packages Built ===' && \
		find bin/packages -name 'mini-mwan*.ipk' -o -name 'luci-app-mini-mwan*.ipk' | xargs ls -lh 2>/dev/null || echo 'Check build logs for errors'"

# Fetch/discover available packages in feeds
feeds-fetch:
	@echo "=== Fetching feeds (discovering packages) ==="
	docker-compose run --rm openwrt-sdk scripts/feeds update -i -a

# Register feeds into build system (symlink packages)
feeds-register:
	@echo "=== Registering feeds (symlinking packages) ==="
	docker-compose run --rm openwrt-sdk scripts/feeds install -a

# Open a shell in the build container
shell:
	docker-compose run --rm openwrt-sdk bash

# Show help
help:
	@echo "Mini-MWAN Build System"
	@echo ""
	@echo "This Makefile orchestrates docker-compose builds using official package structure."
	@echo "For fast development iteration, use VS Code devcontainer (uses Makefile.devcontainer)."
	@echo ""
	@echo "Available targets:"
	@echo "  all            - Fetch feeds, register, and build (default)"
	@echo "  build          - Build both packages only (assumes feeds ready)"
	@echo "  feeds-fetch    - Fetch/discover packages from feeds (using 'feeds update')"
	@echo "  feeds-register - Register feeds into build system (using 'feeds install')"
	@echo "  shell          - Open shell in build container for debugging"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  make           # Full build from scratch"
	@echo "  make build     # Quick rebuild (feeds already set up)"
