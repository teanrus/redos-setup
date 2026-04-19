# 🤝 Руководство по участию в разработке

[![Version](https://img.shields.io/badge/version-3.0.0-blue?style=for-the-badge)](https://github.com/teanrus/redos-setup/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Go Report Card](https://goreportcard.com/badge/github.com/teanrus/redos-setup?style=for-the-badge)](https://goreportcard.com/report/github.com/teanrus/redos-setup)
[![Go Version](https://img.shields.io/badge/Go-1.21+-00ADD8?style=for-the-badge&logo=go)](https://golang.org/)
[![РЕД ОС](https://img.shields.io/badge/РЕД%20ОС-7.3%20|%208.0-red?style=for-the-badge&logo=linux)](https://redos.ru/)
[![GitHub Stars](https://img.shields.io/github/stars/teanrus/redos-setup?style=for-the-badge&logo=github)](https://github.com/teanrus/redos-setup/stargazers)
[![Contributors](https://img.shields.io/github/contributors/teanrus/redos-setup?style=for-the-badge)](https://github.com/teanrus/redos-setup/graphs/contributors)

**redos-setup** — проект с открытым исходным кодом. Мы приветствуем любую помощь: от сообщений об ошибках до полноценных pull request'ов.

---

## 📋 Содержание

- [Способы участия](#-способы-участия)
- [Настройка окружения](#-настройка-окружения)
- [Процесс разработки](#-процесс-разработки)
- [Стандарты кода](#-стандарты-кода)
- [Тестирование](#-тестирование)
- [Документация](#-документация)
- [Создание релизов](#-создание-релизов)
- [Получение помощи](#-получение-помощи)

---

## 🎯 Способы участия

### 1. Сообщение об ошибке 🐛

- Проверьте, нет ли уже такого issue в [GitHub Issues](https://github.com/teanrus/redos-setup/issues)
- Используйте шаблон "Bug Report"
- Укажите версию ОС, версию CLI, логи ошибки

### 2. Предложение новой функции ✨

- Создайте issue с меткой `enhancement`
- Опишите проблему, которую решает функция
- Предложите пример использования

### 3. Pull Request 📥

- Форкните репозиторий
- Создайте ветку `feature/название` или `fix/название`
- Следуйте стандартам кода
- Опишите изменения в PR

### 4. Тестирование на реальном железе 🖥️

- Протестируйте на РЕД ОС 7.3 и 8.0
- Поделитесь результатами в Issues
- Сообщите о найденных проблемах

### 5. Документация 📚

- Исправьте опечатки в README
- Дополните примеры использования
- Переведите документацию на английский

### 6. Помощь другим пользователям 💬

- Отвечайте на вопросы в Issues
- Делитесь опытом использования

---

## 🛠️ Настройка окружения

### Требования

| Компонент | Минимальная версия |
|-----------|-------------------|
| **Go** | 1.21+ |
| **Git** | 2.0+ |
| **Make** | 4.0+ |
| **РЕД ОС** | 7.3 или 8.0 (для тестирования) |

### Установка окружения

```bash
# 1. Клонирование репозитория
git clone https://github.com/teanrus/redos-setup.git
cd redos-setup

# 2. Установка зависимостей
make deps

# 3. Сборка проекта
make build

# 4. Запуск тестов
make test

# 5. Установка (опционально)
sudo make install
```

## Настройка IDE

### Для VS Code

```json
// .vscode/settings.json
{
    "go.lintTool": "golangci-lint",
    "go.lintFlags": ["--fast"],
    "go.formatTool": "goimports",
    "editor.formatOnSave": true,
    "go.testFlags": ["-v", "-race"]
}
```

### Для GoLand

- Включите Go Modules
- Настройте линтер: `golangci-lint`
- Установите форматтер: `goimports`

## 🔄 Процесс разработки

### Git Flow

```text
main
  ├── develop
  │    ├── feature/component-name
  │    ├── fix/bug-description
  │    └── docs/update-readme
  └── release/v3.0.0
```

## Стандартные ветки

| Ветка     | Назначение                       |
| :-------- | :------------------------------- |
| main      | Стабильная версия, только релизы |
| develop   | Интеграционная ветка             |
| feature/* | Новые функции                    |
| fix/*     | Исправление багов                |
| docs/*    | Обновление документации          |
| release/* | Подготовка релиза                |

## Коммиты

Используйте Conventional Commits:

```bash
# Формат
<type>(<scope>): <subject>

# Примеры
feat(installer): добавить поддержку РЕД ОС 8
fix(downloader): исправить таймаут при загрузке
docs(readme): обновить список компонентов
test(security): добавить тесты для КриптоПро
refactor(logger): оптимизировать вывод логов
chore(deps): обновить зависимости
```

### Типы коммитов

- `feat` - новая функция
- `fix` - исправление бага
- `docs` - документация
- `test` - тесты
- `refactor` - рефакторинг
- `chore` - вспомогательные задачи
- `perf` - улучшение производительности

## Pull Request

Шаблон PR:

```markdown
## Описание
Краткое описание изменений

## Тип изменений
- [ ] 🐛 Bug fix
- [ ] ✨ New feature
- [ ] 📚 Documentation
- [ ] 🧪 Tests
- [ ] 🔧 Configuration

## Тестирование
- [ ] Протестировано на РЕД ОС 7.3
- [ ] Протестировано на РЕД ОС 8.0
- [ ] Пройдены unit-тесты

## Скриншоты (если применимо)

## Дополнительная информация
```

## Проверка перед PR

```bash
# 1. Запустите тесты
make test

# 2. Проверьте форматирование
gofmt -l .

# 3. Запустите линтер
golangci-lint run

# 4. Соберите проект
make build
```

## 📏 Стандарты кода

### Go

```go
// Именование
var camelCase          // локальные переменные
var PascalCase         // экспортируемые типы/функции
const CONSTANT_VALUE   // константы

// Структура пакета
package installer

import (
    "fmt"
    "os"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

// Структуры с комментариями
type Installer struct {
    nonInteractive bool   // флаг неинтерактивного режима
    workDir        string // рабочая директория
}

// Функции с документацией
// InstallComponent устанавливает указанный компонент
func (i *Installer) InstallComponent(name string) error {
    // Реализация
}

// Обработка ошибок
if err := i.runCommand("dnf", "update"); err != nil {
    return fmt.Errorf("ошибка обновления: %w", err)
}
```

### Bash (для вспомогательных скриптов)

```bash
#!/bin/bash
# Описание скрипта

set -euo pipefail  # Строгий режим

# Переменные только в UPPER_CASE
WORK_DIR="/home/inst"
MAX_RETRIES=3

# Функции с описанием
# install_telegram - установка Telegram
install_telegram() {
    local version="$1"  # локальные переменные
    
    if [[ -z "$version" ]]; then
        echo "Ошибка: версия не указана"
        return 1
    fi
    
    # Код установки
}
```

### Структура файлов

```text
internal/
├── installer/
│   ├── installer.go   # основной интерфейс
│   ├── base.go        # базовая система
│   ├── security.go    # криптография и безопасность
│   └── *_test.go      # тесты для каждого файла
```

## 🧪 Тестирование

### Unit-тесты

```go
// internal/installer/installer_test.go
package installer

import (
    "testing"
    "github.com/stretchr/testify/assert"
)

func TestInstallComponent(t *testing.T) {
    tests := []struct {
        name      string
        component string
        wantError bool
    }{
        {"Установка Telegram", "telegram", false},
        {"Неизвестный компонент", "unknown", true},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            installer := NewInstaller(true, true, false)
            err := installer.installComponent(tt.component)
            
            if tt.wantError {
                assert.Error(t, err)
            } else {
                assert.NoError(t, err)
            }
        })
    }
}
```

### Интеграционные тесты

```bash
# test/integration.sh
#!/bin/bash

# Тест установки Telegram
echo "=== Тест: установка Telegram ==="
sudo ./redos-setup install --components telegram --yes
assert_success "Telegram должен установиться"

# Тест проверки совместимости
echo "=== Тест: проверка совместимости ==="
./redos-setup check | grep -q "Совместимо"
assert_success "Проверка совместимости должна работать"
```

### Запуск тестов

```bash
# Все тесты
make test

# Только unit-тесты
go test -v ./internal/...

# Тесты с покрытием
go test -cover ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Интеграционные тесты (требуют прав root)
sudo bash test/integration.sh
```

## 📚 Документация

### Комментарии в коде

```go
// detectOSVersion определяет версию операционной системы
// Возвращает структуру OSVersion или ошибку
func detectOSVersion() (*OSVersion, error) {
    // Реализация
}
```

### Обновление README

При добавлении новых компонентов:

- Добавьте компонент в таблицу в README
- Обновите список в команде redos-setup list
- Добавьте пример использования

### Создание примеров

```bash
# examples/basic-setup.sh
#!/bin/bash
# Базовый сценарий настройки АРМ

# Установка базовой системы
sudo redos-setup install --components base-system --yes

# Установка мессенджеров
sudo redos-setup install --components telegram,vk --yes

# Установка криптографии (если ОС 8)
if redos-setup check | grep -q "РЕД ОС 8"; then
    sudo redos-setup install --components cryptopro,vipnet --yes
fi
```

## 🚀 Создание релизов

### Процесс релиза

```bash
# 1. Обновите версию
vim pkg/cli/commands.go  # измените version
vim README.md            # обновите версию

# 2. Запустите тесты
make test

# 3. Создайте тег
git tag -a v3.0.0 -m "Release v3.0.0"
git push origin v3.0.0

# 4. Соберите пакеты
make package-deb
make package-rpm

# 5. Загрузите файлы в GitHub Release
# - build/redos-setup-linux-amd64
# - redos-setup-3.0.0.deb
# - redos-setup-3.0.0.rpm
```

### Шаблон релиза

```markdown
## 🚀 Версия 3.0.0

### ✨ Новые функции
- Поддержка РЕД ОС 8
- CLI интерфейс
- Проверка совместимости компонентов

### 🐛 Исправления
- Исправлена ошибка загрузки больших файлов
- Улучшена обработка сетевых ошибок

### 📦 Установка
```

```bash
curl -sL https://install.redos-setup.ru | bash
```

```markdown
**Скачать:** [redos-setup-3.0.0.deb](link) | [redos-setup-3.0.0.rpm](link)
```

## 💬 Получение помощи

Каналы связи

- GitHub Issues github.com/teanrus/redos-setup/issues
- Email <tyanrv@lbt.yanao.ru>

## Как задавать вопросы

### Хороший вопрос

```text
ОС: РЕД ОС 8.0
Версия CLI: 3.0.0
Команда: redos-setup install --components cryptopro

Проблема: при установке КриптоПро возникает ошибка:
"dependency resolution failed"

Лог: [ссылка на pastebin]
```

### Плохой вопрос

```text
"Не работает, помогите"
```

## 📝 Лицензия

Участвуя в проекте, вы соглашаетесь с условиями MIT License.

## 🌟 Благодарности

Спасибо всем, кто помогает развивать проект!

## Вместе мы сделаем redos-setup лучше! 🚀
