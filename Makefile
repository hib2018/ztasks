.PHONY: build test test-core test-go test-contract fmt fmt-check

build:
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/.zig-global-cache zig build --build-file core/build.zig --cache-dir .zig-cache
	mkdir -p dist
	cd app && GOCACHE=$(CURDIR)/.go-build-cache go build -o ../dist/ztasks ./cmd/ztasks

test: test-core test-go test-contract

test-core:
	ZIG_GLOBAL_CACHE_DIR=$(CURDIR)/.zig-global-cache zig build --build-file core/build.zig --cache-dir .zig-cache test

test-go:
	cd app && GOCACHE=$(CURDIR)/.go-build-cache go test ./...

test-contract:
	cd tests && GOCACHE=$(CURDIR)/.go-build-cache go test ./...

fmt:
	zig fmt core/build.zig core/src
	cd app && go fmt ./...
	cd tests && go fmt ./...

fmt-check:
	zig fmt --check core/build.zig core/src
	test -z "$$(gofmt -l app)"
	test -z "$$(gofmt -l tests)"
