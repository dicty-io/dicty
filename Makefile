# Dicty - Fast, private AI voice dictation and documentation for macOS
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Colors for terminal output
BOLD  := \033[1m
GREEN := \033[32m
CYAN  := \033[36m
RESET := \033[0m

.PHONY: help setup dev test test-backend test-swift build clean whisper

## help: Display this help message
help:
	@echo -e "$(BOLD)Dicty Development Makefile$(RESET)"
	@echo ""
	@echo -e "$(BOLD)Usage:$(RESET) make $(CYAN)<target>$(RESET)"
	@echo ""
	@echo -e "$(BOLD)Targets:$(RESET)"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/## //g' | awk 'BEGIN {FS = ": "}; {printf "  $(CYAN)%-16s$(RESET) %s\n", $$1, $$2}'

## setup: One-command contributor setup (venv, deps, whisper, client build)
setup:
	@echo -e "$(BOLD)$(GREEN)[1/4] Configuring executable permissions...$(RESET)"
	@chmod +x scripts/*.sh *.sh 2>/dev/null || true
	@echo -e "$(BOLD)$(GREEN)[2/4] Setting up Python virtual environment and dependencies...$(RESET)"
	@./scripts/setup_runner_env.sh
	@echo -e "$(BOLD)$(GREEN)[3/4] Compiling / restoring local whisper.cpp binaries...$(RESET)"
	@./scripts/compile_whisper.sh
	@echo -e "$(BOLD)$(GREEN)[4/4] Building Swift client (DictyClient)...$(RESET)"
	@./scripts/check_engine_endpoint.sh
	@cd DictyClient && swift build
	@if [ ! -f .env ] && [ -f .env.example ]; then \
		echo ""; \
		echo "ℹ️  Optional: Copy .env.example to .env to configure cloud LLM API keys."; \
	fi
	@echo ""
	@echo -e "$(BOLD)$(GREEN)✨ Dicty environment is fully configured! Run 'make dev' to start.$(RESET)"

## dev: Launch Dicty in development mode with live source engine
dev:
	@if [ ! -f .venv/bin/python3 ] || [ ! -f bin/whisper.cpp/build/bin/whisper-server ]; then \
		echo -e "$(CYAN)[*] Environment not initialized. Running 'make setup' first...$(RESET)"; \
		$(MAKE) setup; \
	fi
	@./scripts/run_client.sh

## test: Run complete test suite (backend Python tests + Swift client tests)
test:
	@chmod +x scripts/run_tests.sh
	@./scripts/run_tests.sh

## test-backend: Run backend Python test suite only
test-backend:
	@chmod +x scripts/run_tests.sh
	@./scripts/run_tests.sh --backend-only

## test-swift: Run Swift client tests
test-swift:
	@cd DictyClient && swift test

## whisper: Compile whisper.cpp binaries with Apple Silicon Metal acceleration
whisper:
	@chmod +x scripts/compile_whisper.sh
	@./scripts/compile_whisper.sh

## build: Build Swift client in release mode
build:
	@cd DictyClient && swift build -c release

## clean: Remove build artifacts, cached binaries, and temporary test files
clean:
	@echo -e "$(CYAN)[*] Cleaning build artifacts...$(RESET)"
	@rm -rf DictyClient/.build
	@rm -rf bin/whisper.cpp/build
	@rm -rf dist build *.egg-info
	@rm -f *.wav *.zip crash_dump.txt engine_crash.txt engine_log.txt dicty_events.log out.log
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo -e "$(GREEN)[+] Clean completed.$(RESET)"
