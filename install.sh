#!/bin/bash
# Быстрая установка redos-setup CLI

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Установка redos-setup CLI для РЕД ОС 7.3/8          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка Go
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}⚠️  Go не установлен. Устанавливаем...${NC}"
    
    # Установка Go
    if command -v dnf &> /dev/null; then
        sudo dnf install -y golang
    else
        echo -e "${RED}❌ Не удалось установить Go. Установите Go 1.21+ вручную${NC}"
        exit 1
    fi
fi

GO_VERSION=$(go version | grep -oP 'go\d+\.\d+' | sed 's/go//')
if [ "$(echo "$GO_VERSION < 1.21" | bc)" -eq 1 ]; then
    echo -e "${YELLOW}⚠️  Версия Go $GO_VERSION. Рекомендуется Go 1.21+${NC}"
fi

echo -e "${GREEN}✅ Go установлен: $(go version)${NC}"

# Клонирование или обновление репозитория
TEMP_DIR="/tmp/redos-setup-cli"

if [ -d "$TEMP_DIR" ]; then
    echo -e "${BLUE}Обновление репозитория...${NC}"
    cd "$TEMP_DIR"
    git pull
else
    echo -e "${BLUE}Клонирование репозитория...${NC}"
    git clone https://github.com/teanrus/redos-setup.git "$TEMP_DIR"
    cd "$TEMP_DIR"
fi

# Сборка
echo -e "${BLUE}Сборка CLI...${NC}"
make build

# Установка
echo -e "${BLUE}Установка в систему...${NC}"
sudo cp build/redos-setup /usr/local/bin/
sudo chmod +x /usr/local/bin/redos-setup

# Создание конфигурации
sudo mkdir -p /etc/redos-setup
if [ -f "configs/default.yaml" ]; then
    sudo cp configs/default.yaml /etc/redos-setup/config.yaml
fi

# Очистка
cd /
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}✅ Установка завершена!${NC}"
echo ""
echo -e "${BLUE}📖 Краткая инструкция:${NC}"
echo "  • Показать справку:      redos-setup --help"
echo "  • Список компонентов:    redos-setup list"
echo "  • Проверка совместимости: redos-setup check"
echo "  • Установка:             sudo redos-setup install --components telegram,vipnet --yes"
echo ""
echo -e "${YELLOW}⚠️  Примечание: для работы с системными компонентами требуются права root${NC}"