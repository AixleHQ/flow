# AI Engine Docker Management
.PHONY: deps workflows test check lint lint-fix format help

default: help

deps:
	uv sync --all-groups --frozen

workflows:
	python scripts/generate_workflow_constants.py

test:
	ENVIRONMENT=test pytest tests/ -n auto

check: lint test

lint: lint-ruff lint-format

lint-ruff:
	ruff check .

lint-mypy:
	mypy .

lint-format:
	ruff format . --check

format: format-fix lint-ruff-fix

format-fix:
	ruff format .

lint-ruff-fix:
	ruff check . --fix

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  deps - Install dependencies"
	@echo "  workflows - Generate workflow constants"
	@echo "  test - Run tests"
	@echo "  check - Run linters and tests"
	@echo "  lint - Run ruff linter"
	@echo "  lint-ruff - Run ruff linter"
	@echo "  lint-ruff-fix - Run ruff linter and fix issues"
	@echo "  lint-mypy - Run mypy type checker"
	@echo "  format - Format code"
	@echo "  help - Show this help message"
