.PHONY: help install uninstall build-operator build-dashboard test clean

help:
	@echo "SIAB - Secure Infrastructure as a Box"
	@echo ""
	@echo "Available targets:"
	@echo "  install          - Install SIAB platform"
	@echo "  uninstall        - Uninstall SIAB platform"
	@echo "  build-operator   - Build SIAB operator container"
	@echo "  build-dashboard  - Build dashboard container"
	@echo "  test             - Run tests"
	@echo "  clean            - Clean build artifacts"

install:
	@echo "Installing SIAB..."
	@./install.sh

uninstall:
	@echo "Uninstalling SIAB..."
	@./uninstall.sh

build-operator:
	@echo "Building SIAB operator..."
	cd operator && docker build -t ghcr.io/morbidsteve/siab-operator:latest .

build-dashboard:
	@echo "Building dashboard..."
	cd dashboard && docker build -t ghcr.io/morbidsteve/siab-dashboard:latest .

test:
	@echo "Running tests..."
	@cd operator && go test ./... -v

clean:
	@echo "Cleaning..."
	@rm -rf operator/bin
	@rm -rf build/
