.PHONY: build install clean test run deps

BINARY_NAME=redos-setup
VERSION=3.0.0
BUILD_DIR=build
BUILD_DATE=$(shell date -u +%Y-%m-%d_%H:%M:%S)
LDFLAGS=-ldflags "-X main.version=$(VERSION) -X main.buildDate=$(BUILD_DATE)"

build: deps
	@echo "🔨 Сборка $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) cmd/redos-setup/main.go
	@echo "✅ Сборка завершена: $(BUILD_DIR)/$(BINARY_NAME)"

install: build
	@echo "📦 Установка $(BINARY_NAME) в /usr/local/bin..."
	sudo cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/
	sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	sudo mkdir -p /etc/redos-setup
	sudo cp configs/default.yaml /etc/redos-setup/config.yaml
	@echo "✅ Установка завершена"
	@echo "Используйте: sudo $(BINARY_NAME) --help"

clean:
	@echo "🧹 Очистка..."
	rm -rf $(BUILD_DIR)
	rm -rf rpmbuild
	rm -rf release
	go clean

test:
	@echo "🧪 Запуск тестов..."
	go test -v ./...

run: build
	sudo $(BUILD_DIR)/$(BINARY_NAME) $(ARGS)

deps:
	@echo "📦 Установка зависимостей..."
	go mod download
	go mod tidy

# Сборка для всех платформ
build-all: deps
	@echo "🔨 Сборка для всех платформ..."
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 cmd/redos-setup/main.go
	GOOS=linux GOARCH=386 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-386 cmd/redos-setup/main.go
	GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 cmd/redos-setup/main.go
	@echo "✅ Сборка завершена"

# Создание RPM пакета
package-rpm: build-all
	@echo "📦 Создание RPM пакета..."
	@echo "Устанавливаем rpm-build..."
	sudo apt-get update && sudo apt-get install -y rpm 2>/dev/null || true
	sudo dnf install -y rpm-build 2>/dev/null || true
	
	@mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	@cp $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 rpmbuild/SOURCES/$(BINARY_NAME)
	
	@VERSION=$(VERSION); \
	sed "s/VERSION_PLACEHOLDER/$$VERSION/g" scripts/redos-setup.spec.in > rpmbuild/SPECS/redos-setup.spec
	
	@rpmbuild -bb rpmbuild/SPECS/redos-setup.spec --define "_topdir $(PWD)/rpmbuild"
	@mkdir -p release
	@cp rpmbuild/RPMS/x86_64/*.rpm release/ 2>/dev/null || true
	@cp rpmbuild/RPMS/noarch/*.rpm release/ 2>/dev/null || true
	@echo "✅ RPM пакет создан в директории release/"

# CI/CD цели
ci-deps:
	@echo "Installing CI dependencies..."
	go mod download
	go mod verify

ci-lint:
	@echo "Running linter..."
	golangci-lint run --timeout=5m

ci-test:
	@echo "Running tests..."
	go test -race -coverprofile=coverage.out -covermode=atomic ./...
	go tool cover -func=coverage.out

ci-build:
	@echo "Building for CI..."
	mkdir -p build
	go build -o build/redos-setup cmd/redos-setup/main.go

ci: ci-deps ci-lint ci-test ci-build
	@echo "CI completed successfully!"

help:
	@echo "Доступные команды:"
	@echo "  make build        - Собрать бинарный файл"
	@echo "  make install      - Установить в систему"
	@echo "  make clean        - Очистить временные файлы"
	@echo "  make test         - Запустить тесты"
	@echo "  make run ARGS=... - Запустить с аргументами"
	@echo "  make deps         - Установить зависимости Go"
	@echo "  make build-all    - Собрать для всех платформ"
	@echo "  make package-rpm  - Создать RPM пакет"