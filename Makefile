.PHONY: build build-app build-cli test clean setup download-models run help

# Default model
MODEL ?= large-v3-v20240930_626MB

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: build-app build-cli ## Build everything

build-app: ## Build the SwiftUI app
	swift build -c release --product meeting-taker

build-cli: ## Build the CLI tool
	swift build -c release --product mtaker

test: ## Run tests
	swift test

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build

setup: ## Run full setup (dependencies + models + build)
	./setup.sh

download-models: ## Download ML models
	./setup.sh --skip-models 0

run: build-app ## Build and run the app
	.open MeetingTaker.app

serve: build-cli ## Build and start the CLI server
	.build/release/mtaker serve
