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

build-all: deps
	@echo "🔨 Сборка для всех платформ..."
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 cmd/redos-setup/main.go
	GOOS=linux GOARCH=386 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-386 cmd/redos-setup/main.go
	@echo "✅ Сборка завершена"

package-deb: build
	@echo "📦 Создание DEB пакета..."
	mkdir -p package/DEBIAN
	mkdir -p package/usr/local/bin
	mkdir -p package/etc/redos-setup
	cp $(BUILD_DIR)/$(BINARY_NAME) package/usr/local/bin/
	cp configs/default.yaml package/etc/redos-setup/config.yaml
	cat > package/DEBIAN/control << EOF
Package: redos-setup
Version: $(VERSION)
Section: admin
Priority: optional
Architecture: amd64
Maintainer: teanrus <tyanrv@lbt.yanao.ru>
Description: CLI для автоматической настройки РЕД ОС 7.3/8
 Инструмент для установки и настройки программного обеспечения
 на РЕД ОС 7.3 и 8.
EOF
	dpkg-deb --build package redos-setup-$(VERSION).deb
	rm -rf package
	@echo "✅ DEB пакет создан: redos-setup-$(VERSION).deb"

package-rpm: build
	@echo "📦 Создание RPM пакета..."
	mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	cp $(BUILD_DIR)/$(BINARY_NAME) rpmbuild/SOURCES/
	cat > rpmbuild/SPECS/redos-setup.spec << EOF
Name: redos-setup
Version: $(VERSION)
Release: 1%{?dist}
Summary: CLI для автоматической настройки РЕД ОС
License: MIT
URL: https://github.com/teanrus/redos-setup

%description
Инструмент для автоматической установки и настройки ПО на РЕД ОС 7.3 и 8.

%install
mkdir -p %{buildroot}/usr/local/bin
cp %{_sourcedir}/redos-setup %{buildroot}/usr/local/bin/
chmod +x %{buildroot}/usr/local/bin/redos-setup

%files
/usr/local/bin/redos-setup

%changelog
* $(date +"%a %b %d %Y") teanrus <tyanrv@lbt.yanao.ru> - $(VERSION)-1
- Initial RPM release
EOF
	rpmbuild -bb rpmbuild/SPECS/redos-setup.spec --define "_topdir $(PWD)/rpmbuild"
	@echo "✅ RPM пакет создан"

.PHONY: help
help:
	@echo "Доступные команды:"
	@echo "  make build       - Собрать бинарный файл"
	@echo "  make install     - Установить в систему"
	@echo "  make clean       - Очистить временные файлы"
	@echo "  make test        - Запустить тесты"
	@echo "  make run ARGS=...- Запустить с аргументами"
	@echo "  make deps        - Установить зависимости Go"
	@echo "  make build-all   - Собрать для всех платформ"
	@echo "  make package-deb - Создать DEB пакет"
	@echo "  make package-rpm - Создать RPM пакет"