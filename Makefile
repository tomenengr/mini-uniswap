.PHONY: build test test-v fmt fmt-check coverage clean frontend-install frontend-typecheck frontend-test frontend-build

build:
	forge build

test:
	forge test

test-v:
	forge test -vvv

fmt:
	forge fmt

fmt-check:
	forge fmt --check

coverage:
	forge coverage

clean:
	forge clean

frontend-install:
	cd frontend && npm install

frontend-typecheck:
	cd frontend && npm run typecheck

frontend-test:
	cd frontend && npm test

frontend-build:
	cd frontend && npm run build
