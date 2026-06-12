IMAGE ?= ftp-proxy-s3
TAG   ?= dev
SHELL_SCRIPTS := s3-fuse.sh start-vsftpd.sh users.sh add_users_in_container.sh

.DEFAULT_GOAL := help
.PHONY: help build lint shellcheck hadolint test up down clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the Docker image (override with IMAGE=/TAG=)
	docker build -t $(IMAGE):$(TAG) .

lint: shellcheck hadolint ## Run all linters

shellcheck: ## Lint the shell scripts and test stubs
	docker run --rm -v "$(CURDIR):/mnt" -e SHELLCHECK_OPTS="-e SC1091" \
		koalaman/shellcheck:stable $(SHELL_SCRIPTS) tests/stubs/*

hadolint: ## Lint the Dockerfile
	docker run --rm -v "$(CURDIR):/repo" -w /repo hadolint/hadolint hadolint Dockerfile

test: ## Run the bats test suite (in a clean Debian container)
	docker run --rm -v "$(CURDIR):/code" -w /code debian:bookworm-slim \
		bash -c 'apt-get update -qq && apt-get install -y -qq bats >/dev/null && bats tests/'

up: ## Start the stack with docker compose (needs env.list)
	docker compose up -d

down: ## Stop the docker compose stack
	docker compose down

clean: ## Remove the locally built image
	-docker rmi $(IMAGE):$(TAG)
