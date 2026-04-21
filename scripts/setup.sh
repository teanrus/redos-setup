#!/bin/bash

##############################################################################
# setup.sh — Автоматизированная настройка РЕД ОС
#
# Описание:
#   Интерактивный скрипт для установки компонентов на РЕД ОС 7.x и 8+.
#   Выполняет выборочную установку системных и прикладных компонентов,
#   определяет версию ОС и загружает артефакты по мере необходимости.
#
# Использование:
#   sudo ./setup.sh
#
# Зависимости: bash, dnf, curl, wget, coreutils
# Опционально: unzip, rpm, tar
##############################################################################

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# === КОНФИГУРАЦИЯ GITHUB ===
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
ASSETS_RELEASE_TAG="${ASSETS_RELEASE_TAG:-packages}"

# === ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ===
OS_MAJOR_VERSION=""
IS_REDOS=0
SELINUX_MODE="unknown"
WORK_DIR="/home/inst"

# === ФУНКЦИИ ===

read_from_terminal() {
    local prompt="$1"
    local answer
    echo -e "$prompt" >&2
    read -r answer < /dev/tty 2>/dev/null || true
    echo "$answer"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1 успешно выполнено${NC}"
    else
        echo -e "${RED}✗ Ошибка при выполнении: $1${NC}"
        exit 1
    fi
}

confirm_installation() {
    local component_name="$1"
    local answer
    answer=$(read_from_terminal "${YELLOW}Установить $component_name? (y/n)${NC}")
    [[ $answer =~ ^[Yy]$ ]]
}

detect_os_version() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}" in
            redos|redos7|redos8) IS_REDOS=1 ;;
        esac
        if [[ "${VERSION_ID:-}" =~ ^([0-9]+) ]]; then
            OS_MAJOR_VERSION="${BASH_REMATCH[1]}"
        fi
    fi
    echo -e "${BLUE}Обнаружена ОС: ${PRETTY_NAME:-$NAME}${NC}"
}

is_redos7() {
    [ "$IS_REDOS" -eq 1 ] && [ "$OS_MAJOR_VERSION" = "7" ]
}

get_assets_release_url() {
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$ASSETS_RELEASE_TAG/$1"
}

download_from_github() {
    local file_name="$1"
    local url
    url=$(get_assets_release_url "$file_name")
    echo -e "${BLUE}Загрузка $file_name...${NC}"
    if wget --progress=bar:force -O "$WORK_DIR/$file_name" "$url" 2>&1; then
        echo -e "${GREEN}✓ $file_name успешно загружен${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка загрузки $file_name${NC}"
        return 1
    fi
}

is_package_installed() {
    rpm -q "$1" &>/dev/null
}

is_repo_configured() {
    local repo_name="$1"
    [ -f "/etc/yum.repos.d/$repo_name.repo" ] || grep -q "^\[$repo_name\]" /etc/yum.repos.d/*.repo 2>/dev/null
}

# === БЛОКИ УСТАНОВКИ ===

install_updates() {
    if confirm_installation "обновление системы"; then
        echo -e "${BLUE}Обновление системы...${NC}"
        dnf clean all
        dnf makecache
        dnf update -y
        check_success "Обновление системы"
    else
        echo -e "${YELLOW}Пропускаем обновление системы${NC}"
    fi
}

install_kernel() {
    if is_redos7 && confirm_installation "ядро (redos-kernels6) для РЕД ОС 7.x"; then
        echo -e "${BLUE}Установка ядра...${NC}"
        if ! is_package_installed redos-kernels6-release; then
            dnf install -y redos-kernels6-release
            check_success "Установка репозитория ядра"
        fi
        dnf update -y
        check_success "Обновление после установки ядра"
        
        if confirm_installation "обновление конфигурации GRUB после установки ядра"; then
            grub2-mkconfig -o /boot/grub2/grub.cfg
            check_success "Обновление GRUB"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку ядра${NC}"
    fi
}

install_extra_packages() {
    if confirm_installation "дополнительные пакеты (pavucontrol, sshfs, pinta, perl-Getopt-Long, perl-File-Copy)"; then
        local packages=("pavucontrol" "sshfs" "pinta" "perl-Getopt-Long" "perl-File-Copy")
        local to_install=()
        for pkg in "${packages[@]}"; do
            if ! is_package_installed "$pkg"; then
                to_install+=("$pkg")
            else
                echo -e "${GREEN}✓ $pkg уже установлен${NC}"
            fi
        done
        if [ ${#to_install[@]} -gt 0 ]; then
            dnf install -y "${to_install[@]}"
            check_success "Установка дополнительных пакетов"
        else
            echo -e "${GREEN}✓ Все дополнительные пакеты уже установлены${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку дополнительных пакетов${NC}"
    fi
}

install_yandex_browser() {
    if confirm_installation "Яндекс.Браузер"; then
        if ! is_package_installed yandex-browser-stable; then
            # Пробуем добавить репозиторий, игнорируя ошибки SSL
            if ! is_repo_configured "yandex-browser"; then
                echo -e "${YELLOW}Предупреждение: проблемы с SSL сертификатом репозитория Яндекс.Браузера${NC}"
                echo -e "${YELLOW}Установка из репозитория может не работать.${NC}"
                dnf install -y yandex-browser-release 2>/dev/null || true
            fi
            if dnf install -y yandex-browser-stable 2>/dev/null; then
                check_success "Установка Яндекс.Браузера"
            else
                echo -e "${RED}✗ Не удалось установить Яндекс.Браузер. Возможно, проблема с сертификатом.${NC}"
            fi
        else
            echo -e "${GREEN}✓ Яндекс.Браузер уже установлен${NC}"
        fi
    fi
}

install_r7_office() {
    if confirm_installation "R7 Office"; then
        if ! is_package_installed r7-office; then
            if ! is_repo_configured "r7-office"; then
                dnf install -y r7-release
                check_success "Установка репозитория R7"
            fi
            dnf install -y r7-office
            check_success "Установка R7 Office"
        else
            echo -e "${GREEN}✓ R7 Office уже установлен${NC}"
        fi
    fi
}

install_max() {
    if confirm_installation "MAX Desktop"; then
        if ! is_package_installed max; then
            if ! is_repo_configured "max"; then
                cat > /etc/yum.repos.d/max.repo << 'EOF'
[max]
name=MAX Desktop
baseurl=https://download.max.ru/linux/rpm/el/9/x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://download.max.ru/linux/rpm/public.asc
sslverify=1
metadata_expire=300
EOF
                rpm --import https://download.max.ru/linux/rpm/public.asc
                check_success "Установка репозитория MAX"
            fi
            dnf install -y max
            check_success "Установка MAX"
        else
            echo -e "${GREEN}✓ MAX уже установлен${NC}"
        fi
    fi
}

install_sreda() {
    if confirm_installation "корпоративный мессенджер Среда"; then
        if ! is_package_installed sreda; then
            if download_from_github "sreda.rpm"; then
                dnf install -y "$WORK_DIR/sreda.rpm"
                check_success "Установка Среда"
                rm -f "$WORK_DIR/sreda.rpm"
            fi
        else
            echo -e "${GREEN}✓ Среда уже установлена${NC}"
        fi
    fi
}

install_chromium_gost() {
    if confirm_installation "браузер Chromium-GOST (с поддержкой ГОСТ)"; then
        if ! is_package_installed chromium-gost-stable; then
            if download_from_github "chromium-gost-139.0.7258.139-linux-amd64.rpm"; then
                dnf install -y "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
                check_success "Установка Chromium-GOST"
                rm -f "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
            fi
        else
            echo -e "${GREEN}✓ Chromium-GOST уже установлен${NC}"
        fi
    fi
}

install_liberation_fonts() {
    if confirm_installation "шрифты Liberation"; then
        if [ ! -d /usr/share/fonts/liberation ] || [ -z "$(ls -A /usr/share/fonts/liberation 2>/dev/null)" ]; then
            if ! command -v unzip &> /dev/null; then
                dnf install -y unzip
            fi
            if download_from_github "Liberation.zip"; then
                mkdir -p /usr/share/fonts/liberation
                unzip -o "$WORK_DIR/Liberation.zip" -d /usr/share/fonts/liberation/
                rm -f "$WORK_DIR/Liberation.zip"
                chmod 644 /usr/share/fonts/liberation/* 2>/dev/null
                fc-cache -fv
                check_success "Установка шрифтов Liberation"
            fi
        else
            echo -e "${GREEN}✓ Шрифты Liberation уже установлены${NC}"
        fi
    fi
}

install_telegram() {
    if confirm_installation "мессенджер Telegram"; then
        if ! command -v telegram &> /dev/null && [ ! -f /opt/telegram/Telegram ]; then
            if download_from_github "tsetup.tar.xz"; then
                cd "$WORK_DIR"
                tar -xJf tsetup.tar.xz
                mkdir -p /opt/telegram
                cp -r Telegram/* /opt/telegram/
                ln -sf /opt/telegram/Telegram /usr/bin/telegram
                cat > /usr/share/applications/telegram.desktop << 'EOF'
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
                cd - > /dev/null
            fi
        else
            echo -e "${GREEN}✓ Telegram уже установлен${NC}"
        fi
    fi
}

install_kaspersky() {
    if confirm_installation "Kaspersky Agent"; then
        if [ ! -d /opt/kaspersky ]; then
            if download_from_github "kasp.tar.gz"; then
                cd "$WORK_DIR"
                tar -xzf kasp.tar.gz
                for script in *.sh; do
                    if [ -f "$script" ]; then
                        chmod +x "$script"
                        ./"$script"
                    fi
                done
                check_success "Установка Kaspersky Agent"
                rm -f kasp.tar.gz *.sh
                cd - > /dev/null
            fi
        else
            echo -e "${GREEN}✓ Kaspersky Agent уже установлен${NC}"
        fi
    fi
}

install_vipnet() {
    if confirm_installation "ViPNet"; then
        echo -e "${GREEN}=== Выбор версии ViPNet ===${NC}"
        echo "1. ViPNet Client (без деловой почты)"
        echo "2. ViPNet + Деловая почта (DP)"
        local choice
        choice=$(read_from_terminal "${YELLOW}Выберите вариант (1 или 2):${NC}")
        
        if [ "$choice" = "1" ]; then
            local client_asset="vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
            if download_from_github "$client_asset"; then
                dnf install -y "$WORK_DIR/$client_asset"
                check_success "Установка ViPNet Client"
                rm -f "$WORK_DIR/$client_asset"
            fi
        elif [ "$choice" = "2" ]; then
            local client_asset="vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
            if download_from_github "$client_asset" && download_from_github "vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"; then
                dnf install -y "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
                check_success "Установка ViPNet + Деловая почта"
                rm -f "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
            fi
        else
            echo -e "${RED}Неверный выбор${NC}"
        fi
    fi
}

install_1c() {
    if confirm_installation "1С:Предприятие"; then
        if [ ! -d /opt/1cv8 ] && [ ! -d /opt/1C ]; then
            if download_from_github "1c.tar.gz"; then
                cd "$WORK_DIR"
                tar -xzf 1c.tar.gz
                rm -f 1c.tar.gz
                if [ -d "lin_8_3_24_1691" ]; then
                    cd lin_8_3_24_1691
                    chmod +x setup-full-8.3.24.1691-x86_64.run fix.sh
                    ./setup-full-8.3.24.1691-x86_64.run
                    ./fix.sh
                    cd "$WORK_DIR"
                    rm -rf lin_8_3_24_1691
                    echo -e "${GREEN}✓ 1С успешно установлена${NC}"
                fi
                cd - > /dev/null
            fi
        else
            echo -e "${GREEN}✓ 1С:Предприятие уже установлена${NC}"
        fi
    fi
}

# === НАСТРОЙКИ ===

setup_trim() {
    if confirm_installation "настройку TRIM для SSD"; then
        systemctl enable --now fstrim.timer
        check_success "Настройка TRIM"
    else
        echo -e "${YELLOW}Пропускаем настройку TRIM${NC}"
    fi
}

update_grub() {
    if confirm_installation "обновление конфигурации GRUB"; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
        check_success "Обновление GRUB"
    else
        echo -e "${YELLOW}Пропускаем обновление GRUB${NC}"
    fi
}

setup_ksg() {
    if confirm_installation "настройку для моноблока KSG"; then
        if [ -f "/etc/gdm/Init/Default" ]; then
            if ! grep -q "xrandr --output HDMI-3 --primary" /etc/gdm/Init/Default; then
                sed -i '/exit 0/i xrandr --output HDMI-3 --primary' /etc/gdm/Init/Default
                check_success "Настройка KSG"
            else
                echo -e "${GREEN}✓ Настройка KSG уже применена${NC}"
            fi
        else
            echo -e "${RED}✗ Файл /etc/gdm/Init/Default не найден${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем настройку KSG${NC}"
    fi
}

# === УПРАВЛЕНИЕ SELINUX ===

print_selinux_help() {
    cat << 'EOF'

=== Справка по управлению SELinux правилами ===

Если во время установки приложений появляются ошибки SELinux, используйте:

1. Просмотр логов нарушений: sudo tail -f /var/log/audit/audit.log
2. Анализ нарушений: sudo sealert -l "*"
3. Автоматическое создание правил: sudo audit2allow -a -M app_policy && sudo semodule -i app_policy.pp

EOF
}

handle_selinux() {
    if [ ! -f /etc/selinux/config ]; then
        return 0
    fi

    local selinux_current
    selinux_current=$(grep '^SELINUX=' /etc/selinux/config | cut -d= -f2)
    
    # Если SELinux отключен, предлагаем включить
    if [ "$selinux_current" = "disabled" ]; then
        echo -e "${YELLOW}=== Включение SELinux ===${NC}"
        echo "SELinux в настоящее время отключен (disabled). Рекомендуется его включить для безопасности."
        echo "Доступные варианты:"
        echo "1. Включить SELinux в режиме enforcing (самый безопасный)"
        echo "2. Включить SELinux в режиме permissive (логирует нарушения, но не блокирует)"
        echo "3. Оставить SELinux отключенным (disabled)"
        
        local answer
        answer=$(read_from_terminal "${YELLOW}Выберите вариант (1, 2 или 3):${NC}")
        
        case "$answer" in
            1)
                sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
                echo -e "${GREEN}✓ SELinux будет включён в режиме enforcing после перезагрузки${NC}"
                echo -e "${YELLOW}Требуется перезагрузка для применения изменений.${NC}"
                print_selinux_help
                ;;
            2)
                sed -i 's/SELINUX=disabled/SELINUX=permissive/' /etc/selinux/config
                echo -e "${GREEN}✓ SELinux будет включён в режиме permissive после перезагрузки${NC}"
                echo -e "${YELLOW}Требуется перезагрузка для применения изменений.${NC}"
                ;;
            3)
                echo -e "${GREEN}✓ SELinux остаётся отключенным${NC}"
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор. SELinux остаётся без изменений.${NC}"
                ;;
        esac
    elif [ "$selinux_current" = "enforcing" ]; then
        # === ИНТЕРАКТИВНЫЙ ВЫБОР ДЛЯ РЕЖИМА ENFORCING ===
        echo -e "${YELLOW}=== Настройка SELinux ===${NC}"
        echo "SELinux в настоящее время активирован (enforcing). Доступные варианты:"
        echo "1. Оставить SELinux в режиме enforcing (самый безопасный, но может потребоваться добавление правил)"
        echo "2. Перевести SELinux в режим permissive (логирует нарушения, но не блокирует)"
        echo "3. Отключить SELinux полностью (disabled) - НЕ рекомендуется"
        
        local answer
        answer=$(read_from_terminal "${YELLOW}Выберите вариант (1, 2 или 3):${NC}")
        
        case "$answer" in
            1)
                echo -e "${GREEN}✓ SELinux остаётся в режиме enforcing${NC}"
                print_selinux_help
                ;;
            2)
                echo -e "${BLUE}Переведение SELinux в режим permissive...${NC}"
                sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
                check_success "Перевод SELinux в режим permissive"
                echo -e "${YELLOW}Требуется перезагрузка для применения изменений. Используйте: sudo reboot${NC}"
                ;;
            3)
                echo -e "${YELLOW}Отключение SELinux...${NC}"
                sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
                check_success "Отключение SELinux"
                echo -e "${YELLOW}Требуется перезагрузка для полного применения изменений. Используйте: sudo reboot${NC}"
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор. SELinux остаётся без изменений.${NC}"
                ;;
        esac
    elif [ "$selinux_current" = "permissive" ]; then
        echo -e "${YELLOW}=== Настройка SELinux ===${NC}"
        echo "SELinux в настоящее время в режиме permissive. Доступные варианты:"
        echo "1. Перевести SELinux в режим enforcing (рекомендуется)"
        echo "2. Оставить SELinux в режиме permissive"
        echo "3. Отключить SELinux полностью (disabled)"
        
        local answer
        answer=$(read_from_terminal "${YELLOW}Выберите вариант (1, 2 или 3):${NC}")
        
        case "$answer" in
            1)
                echo -e "${BLUE}Переведение SELinux в режим enforcing...${NC}"
                sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
                check_success "Перевод SELinux в режим enforcing"
                echo -e "${YELLOW}Требуется перезагрузка для применения изменений.${NC}"
                print_selinux_help
                ;;
            2)
                echo -e "${GREEN}✓ SELinux остаётся в режиме permissive${NC}"
                ;;
            3)
                echo -e "${YELLOW}Отключение SELinux...${NC}"
                sed -i 's/SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
                check_success "Отключение SELinux"
                echo -e "${YELLOW}Требуется перезагрузка для полного применения изменений.${NC}"
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор. SELinux остаётся без изменений.${NC}"
                ;;
        esac
    fi
}

# === НАЧАЛО СКРИПТА ===

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Этот скрипт должен запускаться с правами root${NC}"
    exit 1
fi

if [ ! -e /dev/tty ]; then
    echo -e "${RED}Ошибка: /dev/tty не доступен. Запустите скрипт в интерактивном терминале.${NC}"
    exit 1
fi

detect_os_version

echo -e "${GREEN}=== Начало настройки РЕД ОС ===${NC}"
echo -e "${BLUE}Дата запуска: $(date)${NC}"
echo ""

handle_selinux

mkdir -p "$WORK_DIR"
chmod 755 "$WORK_DIR"
cd "$WORK_DIR" || exit 1
check_success "Создание рабочей директории"

# === ОСНОВНЫЕ БЛОКИ ===
echo -e "${GREEN}=== Основные компоненты ===${NC}"
install_updates
install_kernel
install_extra_packages

# === ОТДЕЛЬНЫЕ ПРОГРАММЫ ===
echo -e "${GREEN}=== Выбор дополнительных программ ===${NC}"
install_yandex_browser
install_r7_office
install_max
install_sreda
install_chromium_gost
install_liberation_fonts
install_telegram
install_kaspersky
install_vipnet
install_1c

# === СИСТЕМНЫЕ НАСТРОЙКИ ===
echo -e "${GREEN}=== Системные настройки ===${NC}"
setup_trim
update_grub
setup_ksg

# === ЗАВЕРШЕНИЕ ===
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo -e "${BLUE}Время завершения: $(date)${NC}"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ВНИМАНИЕ! Для корректной работы рекомендуется перезагрузить систему.${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

if confirm_installation "перезагрузить систему сейчас"; then
    echo -e "${BLUE}Перезагрузка через 5 секунд...${NC}"
    sleep 5
    sync
    reboot
else
    echo -e "${GREEN}Перезагрузка отменена. Выполните: sudo reboot${NC}"
fi