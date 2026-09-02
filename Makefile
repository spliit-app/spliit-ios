# Everything this project needs, from the command line. Xcode is never required.
#
#   make setup        install the tooling
#   make test         fast unit tests (a couple of seconds, no simulator)
#   make build        build the app for the simulator
#   make strings      check the string catalogues against the source
#   make e2e          run the end-to-end suite against the shared server
#   make run          install and launch the app on this worktree's simulator
#   make shot         screenshot that simulator
#   make screenshots  regenerate the App Store screenshots, in every language
#   make frames       re-wrap those captures for the listing, without recapturing
#   make testflight   archive, export and upload a build to TestFlight
#
# Several worktrees can run all of this at once. Two things make that work: each worktree
# drives a simulator of its own (below), and the server is a shared, long-lived resource that
# no single run owns (`e2e-up` / `e2e-down`).

# The device *type* each worktree's simulator is created from.
SIMULATOR ?= iPhone 17 Pro
DEVICE     ?= Sebastien’s iPhone
UNSIGNED   := CODE_SIGNING_ALLOWED=NO

# One simulator per worktree, named after its directory. Two runs must never share a device:
# they would install over each other's app container, and XCUITest's parallel clones are named
# after the device they came from, so even the clones would collide.
SIM_NAME  ?= Spliit $(notdir $(CURDIR))

# XCUITest parallelises by test *class*, cloning a simulator per worker. Keep suites small and
# similar in size, or one long class becomes a pole no worker count can shorten. More workers
# than cores makes things slower, not faster — override with WORKERS=n, and lower it when
# several worktrees are running at once, because each run boots WORKERS clones of its own.
WORKERS   ?= 3
PARALLEL  := -parallel-testing-enabled YES -maximum-parallel-testing-workers $(WORKERS)

# `ScreenshotTests` is in the UI test bundle but is not a test: it photographs the app for the
# App Store listing, and it asserts nothing a suite would miss. `make screenshots` runs it, on a
# device of its own with a pinned clock; every other run leaves it alone.
SKIP_SCREENSHOTS := -skip-testing:SpliitUITests/ScreenshotTests
SCHEME    := Spliit
PROJECT   := Spliit.xcodeproj
E2E_URL   ?= http://localhost:3009/
DESTINATION := platform=iOS Simulator,name=$(SIM_NAME)
BUNDLE_ID := app.spliit.spliitmobile
DERIVED   := build

# Release. The archive and the .ipa are separate steps so a rejected upload can be retried
# without rebuilding — an archive is minutes, an upload is seconds.
ARCHIVE   := $(DERIVED)/Spliit.xcarchive
EXPORT    := $(DERIVED)/export
IPA       := $(EXPORT)/Spliit.ipa

# The App Store Connect API key. altool finds the .p8 itself, by key ID, in
# ~/.appstoreconnect/private_keys — the issuer is the half that can't be derived from it, so
# it comes from the environment: export ASC_ISSUER_ID, or pass it on the command line.
ASC_KEY_ID    ?= 3NJ328MR4F
ASC_ISSUER_ID ?=

.DEFAULT_GOAL := help
.PHONY: help setup generate build build-device device strings test test-live e2e e2e-up e2e-down e2e-seed fixtures screenshots frames run shot sim sim-clean clean lint archive ipa testflight

help:
	@grep -E '^[a-z0-9-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Install the tooling (XcodeGen)
	@command -v xcodegen >/dev/null || brew install xcodegen
	@echo "Tooling ready. Xcode $$(xcodebuild -version | head -1 | cut -d' ' -f2)."

generate: ## Regenerate Spliit.xcodeproj from project.yml
	@xcodegen generate --quiet
	@echo "Generated $(PROJECT)."

$(PROJECT): project.yml
	@$(MAKE) generate

# The device is only created, never booted, so this costs nothing on a run that already has it.
# The four leading spaces in the pattern are load-bearing: `simctl` indents device names by
# exactly that much, and a leftover clone reads as "Clone 1 of $(SIM_NAME)" — without the
# indent, one of those would pass for the device itself and the real one would never be made.
sim: ## Create this worktree's simulator if it doesn't exist yet
	@xcrun simctl list devices | grep -qF '    $(SIM_NAME) (' \
		|| xcrun simctl create '$(SIM_NAME)' '$(SIMULATOR)' >/dev/null

sim-clean: ## Delete this worktree's simulator, and any clones a run left behind
	@for udid in $$(xcrun simctl list devices | grep -F '$(SIM_NAME) (' \
		| sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'); do \
		xcrun simctl shutdown $$udid 2>/dev/null || true; \
		xcrun simctl delete $$udid; \
	done
	@echo "Removed any simulator named $(SIM_NAME)."

build: $(PROJECT) sim ## Build the app for the simulator
	@xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) \
		$(UNSIGNED) \
		-quiet

# Reads what the last build extracted, so it needs one to have happened.
strings: build ## Check the string catalogues against the strings in the source
	@python3 Scripts/check-strings.py $(DERIVED)

test: ## Run the unit suites on the host (no simulator)
	@cd Packages/SpliitKit && swift test

test-live: ## Run the API suites against the local instance (needs `make e2e-up`)
	@cd Packages/SpliitKit && SPLIIT_LIVE_BASE_URL=$(E2E_URL) swift test --filter Live

# One server is enough no matter how many runs are in flight: every group is addressed by the
# ID the server hands back, and `groups.list` takes those IDs as input, so no run can see — let
# alone disturb — another's data. Asking the server first means a run that finds it already up
# never touches Docker, which is both quicker and one less way for two runs to collide.
e2e-up: ## Start the shared Spliit instance on :3009, if it isn't already up
	@curl -sf $(E2E_URL)api/health/readiness >/dev/null || { \
		docker compose -f e2e/compose.yaml up -d --wait; \
		docker compose -f e2e/compose.yaml run --rm --quiet-pull s3-policy >/dev/null; \
	}
	@echo "Spliit is up at $(E2E_URL) — make e2e-down stops it."

e2e-down: ## Stop it and discard its data
	@docker compose -f e2e/compose.yaml down -v

e2e-seed: ## Load fixture groups and expenses into the running instance
	@node e2e/seed.mjs --base-url $(E2E_URL)

fixtures: ## Re-record the API fixtures the unit tests decode
	@node e2e/seed.mjs --base-url $(E2E_URL) \
		--dump Packages/SpliitKit/Tests/SpliitAPITests/Fixtures >/dev/null
	@echo "Fixtures refreshed."

# Deliberately leaves the server running. A run that tore it down on its way out would be
# pulling the floor from under every other worktree testing at the same time — and the database
# lives in tmpfs, so it would take their data with it. Stopping it is `make e2e-down`, on
# purpose, when nothing is using it.
e2e: $(PROJECT) sim ## Full end-to-end run: the UI suite against the shared server
	@$(MAKE) e2e-up
	@xcodebuild test \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) \
		$(UNSIGNED) \
		$(PARALLEL) \
		$(SKIP_SCREENSHOTS) \
		-test-timeouts-enabled YES \
		-maximum-test-execution-time-allowance 180 \
		-quiet

screenshots: $(PROJECT) ## Regenerate the App Store screenshots, in every language
	@Scripts/screenshots.sh

# The framing is a second pass over the captures, so a headline or a colour can be changed
# without photographing the app again — seconds instead of half an hour.
frames: ## Re-wrap the existing captures for the listing
	@swift Scripts/frame-screenshots.swift \
		Docs/app-store/screenshots Docs/app-store/marketing Docs/app-store/captions.json

build-device: $(PROJECT) ## Build a signed build for a physical device
	@xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		-allowProvisioningUpdates \
		-quiet

# Release config, unlike every other build here, and signed for distribution. The build number
# comes from project.yml and must exceed everything App Store Connect has already seen — it
# rejects a duplicate outright, after the upload rather than before it.
archive: $(PROJECT) ## Build a signed App Store archive
	@xcodebuild archive \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE) \
		-allowProvisioningUpdates \
		-quiet
	@echo "Archived $$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' $(ARCHIVE)/Info.plist)" \
		"($$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' $(ARCHIVE)/Info.plist)) to $(ARCHIVE)."

ipa: archive ## Export that archive as an App Store .ipa
	@rm -rf $(EXPORT)
	@xcodebuild -exportArchive \
		-archivePath $(ARCHIVE) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT) \
		-allowProvisioningUpdates \
		-quiet
	@echo "$(IPA)"

# The credential check comes before the build rather than after it, so a missing issuer costs
# a second instead of the minutes an archive takes.
testflight: ## Upload it to TestFlight (needs ASC_ISSUER_ID)
	@test -n "$(ASC_ISSUER_ID)" || { \
		echo "ASC_ISSUER_ID is not set — it's the Issuer ID shown above the key list at"; \
		echo "https://appstoreconnect.apple.com/access/integrations/api, and pairs with"; \
		echo "key $(ASC_KEY_ID). Re-run as: make testflight ASC_ISSUER_ID=<uuid>"; \
		exit 1; }
	@$(MAKE) ipa
	@xcrun altool --upload-app --type ios --file "$(IPA)" \
		--apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER_ID)
	@echo "Uploaded. App Store Connect takes a few minutes to finish processing the build."

device: build-device ## Install and launch on a connected iPhone
	@xcrun devicectl device install app --device "$(DEVICE)" \
		"$$(find $(DERIVED)/Build/Products/Debug-iphoneos -name 'Spliit.app' -maxdepth 2 | head -1)"
	@xcrun devicectl device process launch --device "$(DEVICE)" $(BUNDLE_ID)

# Named rather than `booted`, which is a coin toss the moment anything else is running: a test
# run has clones of its own booted, and `booted` would happily install into one of those.
run: build ## Install and launch the app on this worktree's simulator
	@xcrun simctl boot '$(SIM_NAME)' 2>/dev/null || true
	@open -a Simulator
	@xcrun simctl install '$(SIM_NAME)' \
		"$$(find $(DERIVED)/Build/Products -name 'Spliit.app' -maxdepth 3 | head -1)"
	@xcrun simctl launch --console-pty '$(SIM_NAME)' $(BUNDLE_ID) -baseURL $(E2E_URL)

shot: ## Screenshot this worktree's simulator to build/screenshot.png
	@mkdir -p $(DERIVED)
	@xcrun simctl io '$(SIM_NAME)' screenshot $(DERIVED)/screenshot.png
	@echo "$(DERIVED)/screenshot.png"

clean: ## Remove build output and the generated project
	@rm -rf $(DERIVED) $(PROJECT)
	@cd Packages/SpliitKit && swift package clean
