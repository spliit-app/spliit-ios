# Everything this project needs, from the command line. Xcode is never required.
#
#   make setup        install the tooling
#   make test         fast unit tests (a couple of seconds, no simulator)
#   make build        build the app for the simulator
#   make e2e          bring up a server, run the end-to-end suite, tear it down
#   make run          install and launch the app on a booted simulator
#   make shot         screenshot whatever the simulator is showing

SIMULATOR ?= iPhone 17 Pro
DEVICE     ?= Sebastien’s iPhone
UNSIGNED   := CODE_SIGNING_ALLOWED=NO

# XCUITest parallelises by test *class*, cloning a simulator per worker. Keep suites small and
# similar in size, or one long class becomes a pole no worker count can shorten. More workers
# than cores makes things slower, not faster — override with WORKERS=n.
WORKERS   ?= 3
PARALLEL  := -parallel-testing-enabled YES -maximum-parallel-testing-workers $(WORKERS)
SCHEME    := Spliit
PROJECT   := Spliit.xcodeproj
E2E_URL   ?= http://localhost:3009/
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
BUNDLE_ID := app.spliit.spliitmobile
DERIVED   := build

.DEFAULT_GOAL := help
.PHONY: help setup generate build build-device device test test-live e2e e2e-up e2e-down e2e-seed fixtures run shot clean lint

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Install the tooling (XcodeGen)
	@command -v xcodegen >/dev/null || brew install xcodegen
	@echo "Tooling ready. Xcode $$(xcodebuild -version | head -1 | cut -d' ' -f2)."

generate: ## Regenerate Spliit.xcodeproj from project.yml
	@xcodegen generate --quiet
	@echo "Generated $(PROJECT)."

$(PROJECT): project.yml
	@$(MAKE) generate

build: $(PROJECT) ## Build the app for the simulator
	@xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) \
		$(UNSIGNED) \
		-quiet

test: ## Run the unit suites on the host (no simulator)
	@cd Packages/SpliitKit && swift test

test-live: ## Run the API suites against the local instance (needs `make e2e-up`)
	@cd Packages/SpliitKit && SPLIIT_LIVE_BASE_URL=$(E2E_URL) swift test --filter Live

e2e-up: ## Start a throwaway Spliit instance on :3009
	@docker compose -f e2e/compose.yaml up -d --wait
	@echo "Spliit is up at $(E2E_URL)"

e2e-down: ## Stop it and discard its data
	@docker compose -f e2e/compose.yaml down -v

e2e-seed: ## Load fixture groups and expenses into the running instance
	@node e2e/seed.mjs --base-url $(E2E_URL)

fixtures: ## Re-record the API fixtures the unit tests decode
	@node e2e/seed.mjs --base-url $(E2E_URL) \
		--dump Packages/SpliitKit/Tests/SpliitAPITests/Fixtures >/dev/null
	@echo "Fixtures refreshed."

e2e: $(PROJECT) ## Full end-to-end run: server up, UI tests, server down
	@$(MAKE) e2e-up
	@xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) \
		$(UNSIGNED) \
		$(PARALLEL) \
		-test-timeouts-enabled YES \
		-maximum-test-execution-time-allowance 180 \
		-quiet; \
		status=$$?; \
		$(MAKE) e2e-down; \
		exit $$status

build-device: $(PROJECT) ## Build a signed build for a physical device
	@xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		-quiet

device: build-device ## Install and launch on a connected iPhone
	@xcrun devicectl device install app --device "$(DEVICE)" \
		"$$(find $(DERIVED)/Build/Products/Debug-iphoneos -name 'Spliit.app' -maxdepth 2 | head -1)"
	@xcrun devicectl device process launch --device "$(DEVICE)" $(BUNDLE_ID)

run: build ## Install and launch the app on a booted simulator
	@xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@open -a Simulator
	@xcrun simctl install booted \
		"$$(find $(DERIVED)/Build/Products -name 'Spliit.app' -maxdepth 3 | head -1)"
	@xcrun simctl launch --console-pty booted $(BUNDLE_ID) -baseURL $(E2E_URL)

shot: ## Screenshot the booted simulator to build/screenshot.png
	@mkdir -p $(DERIVED)
	@xcrun simctl io booted screenshot $(DERIVED)/screenshot.png
	@echo "$(DERIVED)/screenshot.png"

clean: ## Remove build output and the generated project
	@rm -rf $(DERIVED) $(PROJECT)
	@cd Packages/SpliitKit && swift package clean
