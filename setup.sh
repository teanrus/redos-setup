#!/bin/bash
# Автоматизированная настройка РЕД ОС 7.3
# GitHub: https://github.com/teanrus/redos-setup
# Версия: 2.1

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === КОНФИГУРАЦИЯ GITHUB ===
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
GITHUB_TAG="v1.0"

# === ФУНКЦИИ ===

# Функция для проверки успешности выполнения команд
check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1 успешно выполнено${NC}"
    else
        echo -e "${RED}✗ Ошибка при выполнении: $1${NC}"
        exit 1
    fi
}

# Функция для проверки наличия команды
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${YELLOW}Устанавливаю $1...${NC}"
        dnf install -y $1
        check_success "Установка $1"
    fi
}

# Функция отображения прогресса
show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Функция скачивания с GitHub
download_from_github() {
    local file_name=$1
    local dest_dir=$2
    
    local url="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$GITHUB_TAG/$file_name"
    
    echo -e "${BLUE}Загрузка $file_name...${NC}"
    
    if wget --progress=bar:force -O "$dest_dir/$file_name" "$url" 2>&1; then
        echo -e "${GREEN}✓ $file_name успешно загружен${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка загрузки $file_name${NC}"
        return 1
    fi
}

# Функция для запроса подтверждения
confirm_installation() {
    local component_name=$1
    local answer
    
    echo -e "${YELLOW}Установить $component_name? (y/n)${NC}"
    read -r answer
    if [[ $answer =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Функция выбора версии ViPNet
select_vipnet_version() {
    echo -e "${GREEN}=== Выбор версии ViPNet ===${NC}"
    echo "1. ViPNet Client (без деловой почты)"
    echo "2. ViPNet + Деловая почта (DP)"
    echo -e "${YELLOW}Выберите вариант (1 или 2):${NC}"
    read -r vipnet_choice
    
    case $vipnet_choice in
        1)
            echo -e "${BLUE}Установка ViPNet Client...${NC}"
            download_from_github "vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm" "$WORK_DIR"
            if [ -f "$WORK_DIR/vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm" ]; then
                dnf install -y "$WORK_DIR/vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
                check_success "Установка ViPNet Client"
                rm -f "$WORK_DIR/vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
            else
                echo -e "${RED}✗ Ошибка загрузки ViPNet Client${NC}"
                return 1
            fi
            ;;
        2)
            echo -e "${BLUE}Установка ViPNet + Деловая почта...${NC}"
            download_from_github "VipNet-DP.tar.gz" "$WORK_DIR"
            if [ -f "$WORK_DIR/VipNet-DP.tar.gz" ]; then
                cd "$WORK_DIR"
                tar -xzf VipNet-DP.tar.gz
                cd VipNet-DP
                for rpm in *.rpm; do
                    if [ -f "$rpm" ]; then
                        dnf install -y "$rpm"
                    fi
                done
                cd "$WORK_DIR"
                rm -rf VipNet-DP
                rm -f VipNet-DP.tar.gz
                check_success "Установка ViPNet + Деловая почта"
            else
                echo -e "${RED}✗ Ошибка загрузки ViPNet-DP.tar.gz${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            return 1
            ;;
    esac
    return 0
}

# Функция установки браузера Chromium-GOST
install_chromium_gost() {
    if confirm_installation "браузер Chromium-GOST (с поддержкой ГОСТ)"; then
        download_from_github "chromium-gost-139.0.7258.139-linux-amd64.rpm" "$WORK_DIR"
        if [ -f "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm" ]; then
            dnf install -y "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
            check_success "Установка Chromium-GOST"
            rm -f "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
        fi
    fi
}

# Функция установки мессенджеров
install_messengers() {
    # СРЕДА
    if confirm_installation "корпоративный мессенджер СРЕДА"; then
        download_from_github "sreda.rpm" "$WORK_DIR"
        if [ -f "$WORK_DIR/sreda.rpm" ]; then
            dnf install -y "$WORK_DIR/sreda.rpm"
            check_success "Установка СРЕДА"
            rm -f "$WORK_DIR/sreda.rpm"
        fi
    fi
    
    # Viber
    if confirm_installation "мессенджер Viber"; then
        download_from_github "viber.rpm" "$WORK_DIR"
        if [ -f "$WORK_DIR/viber.rpm" ]; then
            dnf install -y "$WORK_DIR/viber.rpm"
            check_success "Установка Viber"
            rm -f "$WORK_DIR/viber.rpm"
        fi
    fi
    
    # ВК Мессенджер
    if confirm_installation "мессенджер ВК (VK Messenger)"; then
        download_from_github "vk-messenger.rpm" "$WORK_DIR"
        if [ -f "$WORK_DIR/vk-messenger.rpm" ]; then
            dnf install -y "$WORK_DIR/vk-messenger.rpm"
            check_success "Установка VK Messenger"
            rm -f "$WORK_DIR/vk-messenger.rpm"
        fi
    fi
    
    # Telegram
    if confirm_installation "мессенджер Telegram"; then
        download_from_github "tsetup.tar.xz" "$WORK_DIR"
        if [ -f "$WORK_DIR/tsetup.tar.xz" ]; then
            cd "$WORK_DIR"
            tar -xJf tsetup.tar.xz
            mkdir -p /opt/telegram
            cp -r Telegram/* /opt/telegram/
            ln -sf /opt/telegram/Telegram /usr/bin/telegram
            # Создание ярлыка
            cat > /usr/share/applications/telegram.desktop << EOF
[Desktop Entry]
Name=Telegram
Comment=Telegram Desktop
Exec=/opt/telegram/Telegram
Icon=/opt/telegram/telegram.png
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
EOF
            chmod +x /usr/share/applications/telegram.desktop
            check_success "Установка Telegram"
            rm -rf Telegram
            rm -f tsetup.tar.xz
        fi
    fi
}

# Функция установки шрифтов Liberation
install_liberation_fonts() {
    if confirm_installation "шрифты Liberation"; then
        download_from_github "Liberation.tar.gz" "$WORK_DIR"
        if [ -f "$WORK_DIR/Liberation.tar.gz" ]; then
            cd "$WORK_DIR"
            tar -xzf Liberation.tar.gz
            mkdir -p /usr/share/fonts/liberation
            cp Liberation/* /usr/share/fonts/liberation/
            fc-cache -fv
            check_success "Установка шрифтов Liberation"
            rm -rf Liberation
            rm -f Liberation.tar.gz
        fi
    fi
}

# Функция установки Kaspersky Agent
install_kaspersky() {
    if confirm_installation "Kaspersky Agent"; then
        download_from_github "kasp.tar.gz" "$WORK_DIR"
        if [ -f "$WORK_DIR/kasp.tar.gz" ]; then
            cd "$WORK_DIR"
            tar -xzf kasp.tar.gz
            for script in *.sh; do
                if [ -f "$script" ]; then
                    chmod +x "$script"
                    ./"$script"
                fi
            done
            check_success "Установка Kaspersky Agent"
            rm -f kasp.tar.gz
            rm -f *.sh
        fi
    fi
}

# Функция установки КриптоПро
install_cryptopro() {
    if confirm_installation "КриптоПро и дополнительные пакеты"; then
        echo -e "${GREEN}Установка КриптоПро...${NC}"
        
        dnf install -y ifd-rutokens token-manager gostcryptogui caja-gostcryptogui
        check_success "Установка пакетов для КриптоПро"
        
        download_from_github "kriptopror4.tar.gz" "$WORK_DIR"
        if [ -f "$WORK_DIR/kriptopror4.tar.gz" ]; then
            cd "$WORK_DIR"
            tar -xzf kriptopror4.tar.gz
            cd R4
            if [ -f "install_gui.sh" ]; then
                chmod +x install_gui.sh
                ./install_gui.sh
                check_success "Установка КриптоПро"
            fi
            cd "$WORK_DIR"
            rm -rf R4
            rm -f kriptopror4.tar.gz
        fi
    else
        echo -e "${YELLOW}Пропускаем установку КриптоПро${NC}"
    fi
}

# Функция установки 1С
install_1c() {
    if confirm_installation "1С:Предприятие"; then
        echo -e "${GREEN}Устанавливаю 1С...${NC}"
        
        download_from_github "1c.tar.gz" "$WORK_DIR"
        if [ -f "$WORK_DIR/1c.tar.gz" ]; then
            cd "$WORK_DIR"
            tar -xzf 1c.tar.gz
            rm -f 1c.tar.gz
            
            if [ -d "lin_8_3_24_1691" ]; then
                cd lin_8_3_24_1691
                chmod +x setup-full-8.3.24.1691-x86_64.run fix.sh
                ./setup-full-8.3.24.1691-x86_64.run
                ./fix.sh
                cd ..
                rm -rf lin_8_3_24_1691
                echo -e "${GREEN}✓ 1С успешно установлена${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Пропускаем установку 1С${NC}"
    fi
}

# === НАЧАЛО СКРИПТА ===

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Этот скрипт должен запускаться с правами root${NC}" 
   exit 1
fi

echo -e "${GREEN}=== Начало настройки РЕД ОС 7.3 ===${NC}"
echo -e "${BLUE}Дата запуска: $(date)${NC}"
echo -e "${BLUE}GitHub: https://github.com/$GITHUB_USER/$GITHUB_REPO${NC}"
echo ""

# Отключаем SELinux
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
check_success "Отключение SELinux"

# Настройка DNF
if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf; then
    echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
    check_success "Настройка DNF"
fi

# Создание рабочей директории
WORK_DIR="/home/inst"
mkdir -p "$WORK_DIR"
chmod 755 "$WORK_DIR"
cd "$WORK_DIR" || exit 1
check_success "Создание рабочей директории"

# Проверка наличия необходимых команд
check_command "wget"
check_command "curl"

# === ОПРОС ПОЛЬЗОВАТЕЛЯ ===
echo -e "${GREEN}=== Выбор программ для установки ===${NC}"
echo -e "${YELLOW}Будут загружены только те программы, на которые вы дадите согласие${NC}"
echo ""

# 1. Базовые компоненты (устанавливаются всегда)
echo -e "${BLUE}--- Базовые компоненты (устанавливаются всегда) ---${NC}"

# 2. Шрифты
install_liberation_fonts

# 3. Браузеры
install_chromium_gost

# 4. Мессенджеры
install_messengers

# 5. Kaspersky Agent
install_kaspersky

# 6. КриптоПро
install_cryptopro

# 7. ViPNet (с выбором версии)
if confirm_installation "ViPNet"; then
    select_vipnet_version
else
    echo -e "${YELLOW}Пропускаем установку ViPNet${NC}"
fi

# 8. 1С
install_1c

# === ЗАВЕРШЕНИЕ ===
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo -e "${BLUE}Время завершения: $(date)${NC}"
echo -e "${YELLOW}Рекомендуется перезагрузить систему. Перезагрузить сейчас? (y/n)${NC}"
read -r reboot_now
if [[ $reboot_now =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Перезагрузка...${NC}"
    reboot
fi