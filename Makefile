TEST?=$(shell go list ./...)
COUNT?=1
VET?=$(shell go list ./...)
# Get the current full sha from git
GOPATH=$(shell go env GOPATH)

default: install-build-deps install-gen-deps generate

ci: testrace ## Test in continuous integration

install-gen-deps: ## Install dependencies for code generation
	# to avoid having to tidy our go deps, we `go get` our binaries from a temp
	# dir. `go get` will change our deps and the following deps are not part of
	# out code dependencies; so a go mod tidy will remove them again. `go
	# install` seems to install the last tagged version and we want to install
	# master.
	@(cd $(TEMPDIR) && GO111MODULE=on go get github.com/mna/pigeon@master)
	@(cd $(TEMPDIR) && GO111MODULE=on go get github.com/alvaroloes/enumer@master)

	# grab files from github and install them using go install, then remove files again.
	@mkdir cmd
	@mkdir cmd/struct-markdown
	@curl -sSfL -q https://raw.githubusercontent.com/hashicorp/packer/master/cmd/struct-markdown/main.go -o cmd/struct-markdown/main.go
	@curl -sSfL -q https://raw.githubusercontent.com/hashicorp/packer/master/cmd/struct-markdown/template.go -o cmd/struct-markdown/template.go
	@go install ./cmd/struct-markdown # in the packer repo

	@mkdir cmd/mapstructure-to-hcl2
	@curl -sSfL -q https://raw.githubusercontent.com/hashicorp/packer/master/cmd/mapstructure-to-hcl2/mapstructure-to-hcl2.go -o cmd/mapstructure-to-hcl2/mapstructure-to-hcl2.go
	@go install ./cmd/mapstructure-to-hcl2 # in the packer repo

	@rm -rf cmd

install-lint-deps: ## Install linter dependencies
	# Pinning golangci-lint at v1.23.8 as --new-from-rev seems to work properly; the latest 1.24.0 has caused issues with memory consumption
	@echo "==> Updating linter dependencies..."
	@curl -sSfL -q https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin v1.23.8

lint: install-lint-deps ## Lint Go code
	@if [ ! -z  $(PKG_NAME) ]; then \
		echo "golangci-lint run ./$(PKG_NAME)/..."; \
		golangci-lint run ./$(PKG_NAME)/...; \
	else \
		echo "golangci-lint run ./..."; \
		golangci-lint run ./...; \
	fi

ci-lint: install-lint-deps ## On ci only lint newly added Go source files
	@echo "==> Running linter on newly added Go source files..."
	GO111MODULE=on golangci-lint run --new-from-rev=$(shell git merge-base origin/main HEAD) ./...

fmt: ## Format Go code
	@go fmt ./...

fmt-check: fmt ## Check go code formatting
	@echo "==> Checking that code complies with go fmt requirements..."
	@git diff --exit-code; if [ $$? -eq 1 ]; then \
		echo "Found files that are not fmt'ed."; \
		echo "You can use the command: \`make fmt\` to reformat code."; \
		exit 1; \
	fi

fmt-docs:
	@find ./website/pages/docs -name "*.md" -exec pandoc --wrap auto --columns 79 --atx-headers -s -f "markdown_github+yaml_metadata_block" -t "markdown_github+yaml_metadata_block" {} -o {} \;

# Install js-beautify with npm install -g js-beautify
fmt-examples:
	find examples -name *.json | xargs js-beautify -r -s 2 -n -eol "\n"

# generate runs `go generate` to build the dynamically generated
# source files.
generate: install-gen-deps ## Generate dynamically generated code
	@echo "==> removing autogenerated markdown..."
	@find website/content/ -type f | xargs grep -l '^<!-- Code generated' | xargs rm -f
	@echo "==> removing autogenerated code..."
	@find ./ -type f | xargs grep -l '^// Code generated' | xargs rm -f
	PROJECT_ROOT="$(CURDIR)" go generate ./...
	go fmt bootcommand/boot_command.go
# 	go run ./cmd/generate-fixer-deprecations

generate-check: generate ## Check go code generation is on par
	@echo "==> Checking that auto-generated code is not changed..."
	@git diff --exit-code; if [ $$? -eq 1 ]; then \
		echo "Found diffs in go generated code."; \
		echo "You can use the command: \`make generate\` to reformat code."; \
		echo "ONCE YOU HAVE REGENERATED CODE, IT SHOULD BE COPIED INTO PACKER CORE"; \
		exit 1; \
	fi

test: vet ## Run unit tests
	@go test -count $(COUNT) $(TEST) $(TESTARGS) -timeout=3m

testrace: vet ## Test with race detection enabled
	GO111MODULE=on go test -count $(COUNT) -race $(TEST) $(TESTARGS) -timeout=3m -p=8

# Runs code coverage and open a html page with report
cover:
	go test -count $(COUNT) $(TEST) $(TESTARGS) -timeout=3m -coverprofile=coverage.out
	go tool cover -html=coverage.out
	rm coverage.out

vet: ## Vet Go code
	@go vet $(VET)  ; if [ $$? -eq 1 ]; then \
		echo "ERROR: Vet found problems in the code."; \
		exit 1; \
	fi

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
