.PHONY: install lint typecheck build format check

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
