.PHONY: help build tui test lint install clean packer-build ansible-check fmt tidy

# =============================================================================
# Variables
# =============================================================================
GO           := go
GOFLAGS      := -trimpath
LDFLAGS      := -s -w -X main.version=1.1.0 -X main.commit=$(shell git rev-parse --short HEAD 2>/dev/null || echo "dev") -X main.date=$(shell date -u +%Y%m%d%H%M%S)
BINDIR       := bin
CMDS         := swissknife pmxctl kvmctl apigateway
PYTHON       := python3
SHELLCHECK   := shellcheck
RUFF         := ruff
GOLANGCI     := golangci-lint
ANSIBLELINT  := ansible-lint
TFLINT       := tflint
PACKER       := packer
BATS         := bats
PIP          := pip3

# Directories
GO_DIR       := go
TEST_DIR     := tests
PACKER_DIR   := packer
ANSIBLE_DIR  := proxmox

# =============================================================================
# Targets
# =============================================================================

help: ## Show this help message
	@echo ""
	@echo "  Pulsar v1.1.0"
	@echo "  ============================="
	@echo ""
	@echo "  Usage:  make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Build all Go binaries (swissknife, pmxctl, kvmctl, apigateway)
	@echo "==> Building Go binaries..."
	@mkdir -p $(BINDIR)
	@for cmd in $(CMDS); do \
		echo "    Building $$cmd..."; \
		$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BINDIR)/$$cmd.exe ./$(GO_DIR)/cmd/$$cmd/; \
	done
	@echo "==> Build complete. Binaries in $(BINDIR)/"

tui: build ## Build and launch the interactive TUI
	@echo "==> Launching TUI..."
	@$(BINDIR)/swissknife.exe tui

test: test-go test-py test-bats ## Run all test suites (Go, Python, Bats)
	@echo "==> All tests passed."

test-go: ## Run Go tests
	@echo "==> Running Go tests..."
	cd $(GO_DIR) && $(GO) test -v -race -coverprofile=../coverage-go.out ./...

test-py: ## Run Python tests with pytest
	@echo "==> Running Python tests..."
	$(PYTHON) -m pytest $(TEST_DIR)/pytest/ -v --tb=short

test-bats: ## Run Bats integration tests
	@echo "==> Running Bats tests..."
	$(BATS) $(TEST_DIR)/bats/

lint: lint-go lint-py lint-bash lint-ansible lint-tf ## Run all linters
	@echo "==> All lint checks passed."

lint-go: ## Lint Go code with golangci-lint
	@echo "==> Linting Go code..."
	cd $(GO_DIR) && $(GOLANGCI) run ./...

lint-py: ## Lint Python code with ruff
	@echo "==> Linting Python code..."
	$(RUFF) check $(TEST_DIR)/
	$(RUFF) format --check $(TEST_DIR)/

lint-bash: ## Lint Bash scripts with shellcheck
	@echo "==> Linting Bash scripts..."
	$(SHELLCHECK) --severity=warning kvm/**/*.sh proxm/**/*.sh shared/**/*.sh 2>/dev/null || true

lint-ansible: ## Lint Ansible playbooks
	@echo "==> Linting Ansible playbooks..."
	$(ANSIBLELINT) $(ANSIBLE_DIR)/

lint-tf: ## Lint Terraform configurations
	@echo "==> Linting Terraform configs..."
	$(TFLINT) --recursive --config .tflint.hcl

fmt: fmt-go fmt-py fmt-bash ## Format all source code
	@echo "==> Formatting complete."

fmt-go: ## Format Go code
	@echo "==> Formatting Go code..."
	$(GO) fmt ./$(GO_DIR)/...

fmt-py: ## Format Python code
	@echo "==> Formatting Python code..."
	$(RUFF) format $(TEST_DIR)/

fmt-bash: ## Format Bash scripts with shfmt
	@echo "==> Formatting Bash scripts..."
	@command -v shfmt >/dev/null 2>&1 && shfmt -w -i 4 -ci kvm/**/*.sh proxm/**/*.sh shared/**/*.sh || echo "    shfmt not installed, skipping"

tidy: ## Run go mod tidy and pip-compile
	@echo "==> Tidying dependencies..."
	cd $(GO_DIR) && $(GO) mod tidy
	@echo "==> Done."

install: build ## Install Go binaries to /usr/local/bin
	@echo "==> Installing binaries to /usr/local/bin..."
	@for cmd in $(CMDS); do \
		echo "    Installing $$cmd..."; \
		install -m 755 $(BINDIR)/$$cmd.exe /usr/local/bin/$$cmd; \
	done
	@echo "==> Installation complete."

clean: ## Remove build artifacts and cache directories
	@echo "==> Cleaning build artifacts..."
	@rm -rf $(BINDIR)/
	@rm -rf $(GO_DIR)/dist/
	@rm -f coverage-go.out coverage.html
	@rm -rf $(PACKER_DIR)/output-*/
	@rm -rf $(PACKER_DIR)/packer_cache/
	@rm -rf .pytest_cache/ .mypy_cache/ .ruff_cache/
	@rm -rf $(GO_DIR)/.cache/
	@echo "==> Clean complete."

packer-build: ## Build all Packer templates
	@echo "==> Building Packer templates..."
	@for dir in $(PACKER_DIR)/*/; do \
		if [ -f "$$dir"*.pkr.hcl ] || [ -f "$$dir"*.pkr.json ]; then \
			echo "    Building $$dir..."; \
			$(PACKER) validate "$$dir" && $(PACKER) build "$$dir"; \
		fi; \
	done
	@echo "==> Packer build complete."

ansible-check: ## Syntax-check all Ansible playbooks
	@echo "==> Checking Ansible playbooks..."
	@find $(ANSIBLE_DIR) -name '*.yml' -o -name '*.yaml' | while read -r playbook; do \
		echo "    Checking $$playbook..."; \
		$(PYTHON) -m ansible_playbook --syntax-check "$$playbook" 2>/dev/null || \
		ansible-playbook --syntax-check "$$playbook" 2>/dev/null || \
		echo "    Skipping $$playbook (not a playbook or missing deps)"; \
	done
	@echo "==> Ansible check complete."
