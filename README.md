# 🚀 redos-setup

**Автоматизированная настройка РЕД ОС 7.3 и 8**

[![Version](https://img.shields.io/badge/version-3.0.0-blue?style=for-the-badge)](https://github.com/teanrus/redos-setup/releases)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)
[![Go Report Card](https://goreportcard.com/badge/github.com/teanrus/redos-setup?style=for-the-badge)](https://goreportcard.com/report/github.com/teanrus/redos-setup)
[![Go Version](https://img.shields.io/badge/Go-1.21+-00ADD8?style=for-the-badge&logo=go)](https://golang.org/)
[![РЕД ОС](https://img.shields.io/badge/РЕД%20ОС-7.3%20|%208.0-red?style=for-the-badge&logo=linux)](https://redos.ru/)
[![GitHub Stars](https://img.shields.io/github/stars/teanrus/redos-setup?style=for-the-badge&logo=github)](https://github.com/teanrus/redos-setup/stargazers)

---

## 📖 О проекте

Проект предоставляет два инструмента для автоматической настройки РЕД ОС:

| Версия | Описание | Статус | Рекомендация |
|--------|----------|--------|--------------|
| **v3.0+** | Современный CLI на Go с поддержкой РЕД ОС 8 | ✅ Активен | 🔥 **Рекомендуется** |
| **v2.x** | Классический bash-скрипт для РЕД ОС 7.3 | 📦 Стабилен | Для обратной совместимости |

> 💡 **История проекта**: классический bash-скрипт (`setup.sh`) был моим первым проектом автоматизации для РЕД ОС 7.3. Он отлично работал, но с выходом РЕД ОС 8 потребовалась более гибкая архитектура. Так родился **redos-setup CLI** — полностью переписанный на Go с поддержкой обеих версий ОС.

---

## 🎯 Что нового в CLI v3.0?

- ✅ **Поддержка РЕД ОС 8** — автоматическое определение версии и выбор совместимых компонентов
- ✅ **Модульная архитектура** — каждый компонент в отдельном пакете
- ✅ **CLI интерфейс** — удобные команды и флаги (`install`, `list`, `check`, `version`)
- ✅ **Неинтерактивный режим** — для CI/CD и автоматизации (`--yes`, `--non-interactive`)
- ✅ **Логирование** — цветной вывод + файл лога в `/var/log/redos-setup/`
- ✅ **Конфигурация** — YAML файл для тонкой настройки
- ✅ **Проверка совместимости** — умная фильтрация компонентов под вашу версию ОС

---

## 📦 Установка

### 🚀 Быстрая установка (рекомендуется)

```bash
# Установка CLI версии 3.0
curl -sL https://raw.githubusercontent.com/teanrus/redos-setup/main/install.sh | bash

# Проверка установки
redos-setup --version
redos-setup check
```

## 📥 Классический bash-скрипт (для legacy)

```bash
# Для РЕД ОС 7.3 (старая версия)
curl -sL https://github.com/teanrus/redos-setup/releases/latest/download/setup.sh | sudo bash

# Или с сохранением файла
wget https://github.com/teanrus/redos-setup/releases/latest/download/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

## 🔧 Установка из исходников

```bash
git clone https://github.com/teanrus/redos-setup.git
cd redos-setup
make install
```

## 🎮 Использование CLI

Основные команды

```bash
# Показать справку
redos-setup --help

# Список всех доступных компонентов
redos-setup list

# Проверка совместимости с вашей версией ОС
redos-setup check

# Версия CLI
redos-setup version
```

Установка компонентов

```bash
# Интерактивная установка
sudo redos-setup install --components telegram

# Установка нескольких компонентов
sudo redos-setup install --components telegram,vipnet,1c

# Автоматическая установка (без подтверждений)
sudo redos-setup install --yes --components base-system,telegram

# Принудительная установка (игнорировать ошибки)
sudo redos-setup install --force --components all

# Подробный вывод
sudo redos-setup install --verbose --components cryptopro
```

Примеры для разных сценариев

```bash
# 1. Базовая настройка нового АРМ
sudo redos-setup install --yes --components base-system,trim,grub

# 2. Рабочая станция с мессенджерами
sudo redos-setup install --components telegram,vk,sreda --yes

# 3. Защищенный АРМ с криптографией
sudo redos-setup install --components cryptopro,vipnet,kaspersky --yes

# 4. Полная установка всего ПО (осторожно!)
sudo redos-setup install --components all --force

# 5. Для РЕД ОС 8 с автоматическим выбором версий компонентов
sudo redos-setup check # сначала проверить совместимость
sudo redos-setup install --components base-system,cryptopro,vipnet --yes
```

## 📋 Доступные компоненты

### 🔧 Системные

| Компонент | Описание |
| :--- | :--- |
| base-system | Базовая система (репозитории, ядро, R7 Office, MAX) |
| trim | Настройка TRIM для SSD |
| grub | Обновление конфигурации GRUB |
| ksg | Настройка моноблока KSG |

### 🌐 Браузеры

| Компонент | Описание |
| :--- | :--- |
| chromium | Chromium-GOST (с поддержкой ГОСТ) |
| yandex | Яндекс Браузер для организаций |

### 💬 Мессенджеры

| Компонент | Описание |
| :--- | :--- |
| telegram | Telegram Desktop |
| vk | VK Messenger |
| sreda | Корпоративный мессенджер Среда |

### 🛡️ Безопасность и криптография

| Компонент | Описание |
| :--- | :--- |
| kaspersky | Kaspersky Agent |
| cryptopro | КриптоПро CSP |
| vipnet | ViPNet VPN (Client или Client+DP) |

### 📊 Офисные и приложения

| Компонент | Описание |
| :--- | :--- |
| 1c | 1С:Предприятие |
| fonts | Шрифты Liberation |
| r7-office | R7 Office |
| pavucontrol | Микшер звука |
| sshfs | Монтирование удаленных директорий |
| pinta | Графический редактор |

### 🎯 Особые режимы

| Компонент | Описание |
| :--- | :--- |
| all | Установить всё доступное ПО |
| 🖥️ Системные требования | |
| Параметр | Минимальные требования |
| ОС | РЕД ОС 7.3 или 8.0 |
| Архитектура | x86_64 |
| Права | root (sudo) |
| Интернет | Требуется для загрузки из GitHub |
| RAM | 2 GB (рекомендуется 4 GB) |
| Диск | 5 GB свободного места |
| Go | 1.21+ (только для сборки из исходников) |

## 🔄 Совместимость версий

| Компонент | РЕД ОС 7.3 | РЕД ОС 8.0 |
| :--- | :--- | :--- |
| КриптоПро CSP | 4.x ✅ | 5.0+ ✅ |
| ViPNet | 4.15 ✅    | 4.16+ ✅ |
| Kaspersky Agent | 13.x ✅ | 14.0+ ✅ |
| 1С:Предприятие | 8.3.24 ✅ | 8.3.25+ ✅ |
| Остальные компоненты | ✅ | ✅ |

>💡 CLI автоматически определяет версию ОС и предлагает совместимые версии компонентов.

## 🎨 Цветовая индикация

Цвет	Значение
🟢 Зеленый	Успешное выполнение
🔴 Красный	Ошибка
🟡 Желтый	Предупреждение
🔵 Синий	Информация

## 📊 Сравнение версий

| Функция | Bash-скрипт (v2.x) | Go CLI (v3.0) |
| :--- | :--- | :--- |
| Поддержка РЕД ОС 7.3   | ✅ | ✅ |
| Поддержка РЕД ОС 8     | ❌ | ✅ |
| CLI интерфейс          | ❌ (интерактивный) | ✅ |
| Неинтерактивный режим  | ❌ | ✅ |
| Проверка совместимости | ❌ | ✅ |
| Логирование в файл     | ❌ | ✅ |
| Конфигурация YAML      | ❌ | ✅ |
| Модульная архитектура  | ❌ | ✅ |
| Автовыбор версий       | ❌ | ✅ |
| Простота использования | ✅ | ✅ |
| Размер | ~50 KB  | ~8 MB         |

## 🛠️ Разработка и сборка

```bash
# Клонирование репозитория
git clone https://github.com/teanrus/redos-setup.git
cd redos-setup

# Установка зависимостей
make deps

# Сборка
make build

# Запуск тестов
make test

# Создание DEB пакета
make package-deb

# Создание RPM пакета
make package-rpm
```

## 📁 Структура проекта

```text
redos-setup/
├── cmd/ # Точка входа CLI
│ └── redos-setup/
├── internal/ # Внутренние модули
│ ├── installer/ # Установка компонентов
│ ├── downloader/ # Загрузка с GitHub
│ ├── system/ # Системные настройки
│ └── logger/ # Логирование
├── pkg/ # Публичные пакеты
│ ├── cli/ # CLI команды
│ └── config/ # Конфигурация
├── scripts/ # (резерв) Bash скрипты
├── configs/ # Конфиги по умолчанию
├── setup.sh # 📜 Классический bash-скрипт (v2.x)
├── Makefile # Сборка проекта
├── install.sh # Быстрая установка CLI
└── README.md # Этот файл
```

## 🤝 Вклад в проект

Приветствуются любые предложения и улучшения!

Форкните репозиторий

Создайте ветку для фичи (`git checkout -b feature/amazing-feature`)

Закоммитьте изменения (`git commit -m 'Add amazing feature'`)

Запушьте ветку (`git push origin feature/amazing-feature`)

Откройте `Pull Request`

## 📄 Лицензия
Проект распространяется под лицензией MIT. Подробнее в файле LICENSE.

## 📞 Обратная связь

- 📧 Email: tyanrv@lbt.yanao.ru
- 🐛 GitHub Issues: teanrus/redos-setup/issues
- ⭐ GitHub Releases: teanrus/redos-setup/releases

>⚠️ Важное примечание
>Скрипты предназначены для использования в корпоративной среде.
>
>**Перед запуском убедитесь, что:**
>- Версии устанавливаемого ПО соответствуют требованиям вашей организации
>- У вас есть необходимые лицензии на коммерческое ПО (КриптоПро, 1С, ViPNet)
>- Сделано резервное копирование важных данных
>
>**Авторы не несут ответственности за возможную потерю данных**

## ⭐ Если проект оказался полезным
Поставьте звезду на GitHub — это поможет другим пользователям найти проект!

https://img.shields.io/github/stars/teanrus/redos-setup?style=social
