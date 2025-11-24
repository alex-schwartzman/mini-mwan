# Mini-MWAN Build Orchestration
# Uses docker-compose to build packages with official Makefile structure

.PHONY: all build shell feeds-fetch feeds-register help
.DEFAULT_GOAL := all

# Full build: refetch feeds, register them, then build packages
all: build
	@echo ""
	@echo "=== Full build complete ==="

# Build both packages.
build:
	@echo "=== Building packages (official structure with luci.mk) ==="
	docker-compose run --rm openwrt-sdk-ramips bash -c "\
		scripts/feeds update luci-app-mini-mwan && \
		scripts/feeds install luci-app-mini-mwan && \
		make defconfig && \
		make package/feeds/luci/luci-app-mini-mwan/compile V=s && \
		echo '' && \
		echo '=== Packages Built ===' && \
		find bin/packages -name '*mini-mwan*.ipk' | xargs ls -lh 2>/dev/null || echo 'Check build logs for errors'"

# Open a shell in the build container
shell:
	docker-compose run --rm openwrt-sdk-ramips bash

#listen to localhost:8080 and replace static content for the app
#to make it work, you need to replace "asusrouter" with name of
#your router where to fetch the rest of the LuCI static content
#and don't forget to terminate it with killall -9 nginx
nginx:
	mkdir -p nginx-run/{logs,run,client_body_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}
	nginx -c `pwd`/localhost-development-nginx.conf -p `pwd`

# Open a shell in the build container
check:
	luacheck mini-mwan/files/mini-mwan.lua

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
	@echo "  shell          - Open shell in build container for debugging"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Usage:"
	@echo "  make           # Full build from scratch"
	@echo "  make build     # Quick rebuild (feeds already set up)"
