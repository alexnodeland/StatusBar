.PHONY: build release test lint format format-check check clean install setup dev help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Dev build (arm64, fast)
	@./build.sh

release: ## Release build (universal binary + ZIP)
	@./build.sh --release

test: ## Run unit tests
	@./test.sh

lint: ## Run SwiftLint on Sources/ and Tests/
	@swiftlint lint --strict Sources/ Tests/

format: ## Auto-format Swift files with swift-format
	@swift-format format --in-place --recursive Sources/ Tests/

format-check: ## Check formatting (fails if changes needed)
	@swift-format lint --strict --recursive Sources/ Tests/

check: lint format-check test ## Run lint + format check + tests (CI target)

clean: ## Remove build artifacts
	@rm -rf build/ .build-tests/

setup: ## Install tools and git hooks (one-time bootstrap)
	@brew bundle
	@lefthook install
	@echo "Setup complete."

dev: build ## Build and open the app
	@open ./build/StatusBar.app

install: build ## Build and copy .app to /Applications
	@cp -R build/StatusBar.app /Applications/
	@echo "Installed to /Applications/StatusBar.app"
