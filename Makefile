COMMIT = $(shell git describe --always)
VERSION = $(shell grep Version cli/version.go | sed -E 's/.*"(.+)"$$/\1/')

PHONY: help vendor
.DEFAULT_GOAL := help


build: ## build generate binary on './bin' directory.
	go build -ldflags "-X main.GitCommit=$(COMMIT)" -o bin/exporter_proxy .

buildx: build-linux-amd64 build-linux-arm64 ## build for all platforms
	@echo built for linux/amd64 and linux/arm64

build-linux-amd64: vendor ## build static for linux/amd64
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/exporter_proxy_linux_amd64 .

build-linux-arm64: vendor ### build static for linux/arm64
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o bin/exporter_proxy_linux_arm64 .

test: ## run tests
	go test

test-short: ## run tests (short)
	go test -short

vendor: ## fetch vendor deps
	go mod vendor

release: buildx ## releases files to Github
	gh release create v$(VERSION) -d 'bin/exporter_proxy_linux_arm64' 'bin/exporter_proxy_linux_amd64'
	@echo Release has been drafted. Go to the github page to check it and publish it

help: ## displays this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
