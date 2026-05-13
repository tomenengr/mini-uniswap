.PHONY: build test test-v fmt fmt-check coverage clean

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

