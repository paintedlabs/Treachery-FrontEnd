.PHONY: install lint typecheck build format check \
       ios-test ios-lint ios-build ios-check \
       check-all

# ── Web & Functions ────────────────────────────────────

install:
	cd Treachery && npm ci && cd ../functions && npm ci

lint:
	cd Treachery && npm run lint && cd ../functions && npm run lint

typecheck:
	cd Treachery && npm run typecheck

build:
	cd Treachery && npm run build:web

format:
	cd Treachery && npm run format

check: lint typecheck build

# ── iOS ────────────────────────────────────────────────

ios-test:
	cd Treachery-iOS && xcodebuild test \
		-project Treachery-iOS.xcodeproj \
		-scheme Treachery-iOS \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
		-enableCodeCoverage YES \
		CODE_SIGNING_ALLOWED=NO \
		| xcpretty --color && exit $${PIPESTATUS[0]}

ios-lint:
	swiftlint lint --strict

ios-build:
	cd Treachery-iOS && xcodebuild build \
		-project Treachery-iOS.xcodeproj \
		-scheme Treachery-iOS \
		-destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
		CODE_SIGNING_ALLOWED=NO \
		| xcpretty --color && exit $${PIPESTATUS[0]}

ios-check: ios-lint ios-build ios-test

# ── All Platforms ──────────────────────────────────────

check-all: check ios-check
