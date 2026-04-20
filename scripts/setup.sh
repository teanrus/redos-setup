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
# Опции:
#   Нет опций — скрипт полностью интерактивный.
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
NC='\033[0m' # No Color

# === КОНФИГУРАЦИЯ GITHUB ===
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
ASSETS_RELEASE_TAG="${ASSETS_RELEASE_TAG:-packages}"
# Используем latest релиз вместо фиксированной версии

# === ФУНКЦИИ ===

# Функция для получения URL последнего релиза
get_release_asset_url() {
    local release_tag=$1
    local file_name=$2
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$release_tag/$file_name"
}

get_assets_release_url() {
    local file_name=$1
    get_release_asset_url "$ASSETS_RELEASE_TAG" "$file_name"
}

# Функция для безопасного чтения ввода из терминала
read_from_terminal() {
    local prompt="$1"
    local answer
    echo -e "$prompt" >&2
    read -r answer < /dev/tty 2>/dev/null || true
    echo "$answer"
}

# Функция определения версии ОС и совместимости компонентов
detect_os_version() {
    OS_NAME="Неизвестная ОС"
    OS_VERSION_ID="unknown"
    OS_MAJOR_VERSION=""
    IS_REDOS=0
    CRYPTOPRO_SUPPORTED=0
    VIPNET_SUPPORTED=0

    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_NAME="${PRETTY_NAME:-${NAME:-$OS_NAME}}"
        OS_VERSION_ID="${VERSION_ID:-$OS_VERSION_ID}"
    fi

    case "${ID:-}" in
        redos|redos7|redos8)
            IS_REDOS=1
            ;;
    esac

    if [[ "$OS_VERSION_ID" =~ ^([0-9]+) ]]; then
        OS_MAJOR_VERSION="${BASH_REMATCH[1]}"
    fi

    if [ "$IS_REDOS" -eq 1 ] && [ -n "$OS_MAJOR_VERSION" ]; then
        case "$OS_MAJOR_VERSION" in
            7)
                CRYPTOPRO_SUPPORTED=1
                VIPNET_SUPPORTED=1
                ;;
            *)
                if [ "$OS_MAJOR_VERSION" -ge 8 ]; then
                    CRYPTOPRO_SUPPORTED=1
                    VIPNET_SUPPORTED=1
                fi
                ;;
        esac
    fi
}

# Функция вывода информации о версии ОС и предупреждений о совместимости
show_os_compatibility_info() {
    echo -e "${BLUE}Обнаружена ОС: $OS_NAME${NC}"

    if [ "$IS_REDOS" -ne 1 ]; then
        echo -e "${YELLOW}Внимание: скрипт разработан для РЕД ОС. Текущая ОС не распознана как РЕД ОС.${NC}"
        return
    fi

    if [ -n "$OS_MAJOR_VERSION" ]; then
        echo -e "${BLUE}Основная версия РЕД ОС: $OS_MAJOR_VERSION${NC}"
    fi

    if [ "$OS_MAJOR_VERSION" = "7" ]; then
        echo -e "${GREEN}Режим совместимости: доступны все штатные компоненты скрипта, ViPNet устанавливается из пакетов для РЕД ОС 7.x.${NC}"
    elif [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        echo -e "${YELLOW}Внимание: скрипт изначально разрабатывался и тестировался для РЕД ОС 7.3.${NC}"
        echo -e "${YELLOW}Для РЕД ОС $OS_VERSION_ID ViPNet будет устанавливаться из пакетов для РЕД ОС 8+.${NC}"
        echo -e "${YELLOW}Остальные компоненты будут предложены к установке как обычно.${NC}"
    else
        echo -e "${YELLOW}Не удалось однозначно определить основную версию РЕД ОС. ViPNet будет недоступен для безопасности.${NC}"
    fi
}

# Функция проверки доступности компонента для текущей версии ОС
is_component_supported() {
    local component_name=$1

    case "$component_name" in
        cryptopro)
            [ "$CRYPTOPRO_SUPPORTED" -eq 1 ]
            ;;
        vipnet)
            [ "$VIPNET_SUPPORTED" -eq 1 ]
            ;;
        *)
            return 0
            ;;
    esac
}

# Функция вывода предупреждения о несовместимости компонента
warn_component_not_supported() {
    local component_label=$1
    echo -e "${YELLOW}Пропускаем $component_label: компонент недоступен для ${OS_NAME}.${NC}"
}

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

# Функция скачивания с GitHub (использует latest релиз)
download_from_github() {
    local file_name=$1
    local dest_dir=$2
    
    local url=$(get_assets_release_url "$file_name")
    
    echo -e "${BLUE}Загрузка $file_name...${NC}"
    
    if ! curl -s --head -f "$url" > /dev/null 2>&1; then
        echo -e "${RED}✗ Файл $file_name не найден в release '$ASSETS_RELEASE_TAG'${NC}"
        return 1
    fi
    
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
    
    answer=$(read_from_terminal "${YELLOW}Установить $component_name? (y/n)${NC}")
    if [[ $answer =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Функция для вставки строки перед exit 0
insert_before_exit() {
    local file=$1
    local line=$2
    
    if [ -f "$file" ]; then
        local temp_file=$(mktemp)
        
        while IFS= read -r file_line; do
            if [[ "$file_line" =~ ^[[:space:]]*exit[[:space:]]+0 ]]; then
                echo "$line" >> "$temp_file"
            fi
            echo "$file_line" >> "$temp_file"
        done < "$file"
        
        mv "$temp_file" "$file"
        chmod --reference="$file" "$file" 2>/dev/null || chmod 755 "$file"
        
        echo -e "${GREEN}✓ Строка добавлена перед exit 0 в $file${NC}"
    else
        echo -e "${RED}✗ Файл $file не найден${NC}"
        return 1
    fi
}

# Функция для управления SELinux
handle_selinux() {
    if [ ! -f /etc/selinux/config ]; then
        return 0
    fi

    local selinux_current=$(grep '^SELINUX=' /etc/selinux/config 2>/dev/null | cut -d= -f2)
    
    # Если SELinux отключен, предлагаем его включить
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
                set_selinux_enforcing
                ;;
            2)
                set_selinux_permissive_from_disabled
                ;;
            3)
                echo -e "${GREEN}✓ SELinux остаётся отключенным${NC}"
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор. SELinux остаётся без изменений.${NC}"
                ;;
        esac
    elif [ "$selinux_current" = "enforcing" ]; then
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
                set_selinux_permissive
                ;;
            3)
                set_selinux_disabled
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор. SELinux остаётся без изменений.${NC}"
                ;;
        esac
    fi
}

# Функция для перевода SELinux в режим permissive
set_selinux_permissive() {
    echo -e "${BLUE}Переведение SELinux в режим permissive...${NC}"
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    check_success "Перевод SELinux в режим permissive"
    echo -e "${YELLOW}Требуется перезагрузка для применения изменений. Используйте: sudo reboot${NC}"
}

# Функция для включения SELinux в режим enforcing из disabled
set_selinux_enforcing() {
    echo -e "${BLUE}Включение SELinux в режим enforcing...${NC}"
    sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
    check_success "Включение SELinux в режим enforcing"
    echo -e "${YELLOW}Требуется перезагрузка для применения изменений. Используйте: sudo reboot${NC}"
    echo -e "${BLUE}После перезагрузки система будет работать с SELinux в режиме enforcing (рекомендуется использовать semanage для добавления необходимых правил)${NC}"
    print_selinux_help
}

# Функция для включения SELinux в режим permissive из disabled
set_selinux_permissive_from_disabled() {
    echo -e "${BLUE}Включение SELinux в режим permissive...${NC}"
    sed -i 's/SELINUX=disabled/SELINUX=permissive/' /etc/selinux/config
    check_success "Включение SELinux в режим permissive"
    echo -e "${YELLOW}Требуется перезагрузка для применения изменений. Используйте: sudo reboot${NC}"
    echo -e "${BLUE}В режиме permissive SELinux логирует нарушения, но не блокирует приложения${NC}"
}

# Функция для полного отключения SELinux
set_selinux_disabled() {
    echo -e "${YELLOW}Отключение SELinux...${NC}"
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    check_success "Отключение SELinux"
    echo -e "${YELLOW}Требуется перезагрузка для полного применения изменений. Используйте: sudo reboot${NC}"
}

# Функция для вывода справки по SELinux
print_selinux_help() {
    cat << 'EOF'

=== Справка по управлению SELinux правилами ===

Если во время установки приложений появляются ошибки SELinux, используйте:

1. Просмотр логов нарушений:
   sudo tail -f /var/log/audit/audit.log

2. Анализ нарушений:
   sudo sealert -l "*"

3. Автоматическое создание и применение правил:
   sudo audit2allow -a -M app_policy
   sudo semodule -i app_policy.pp

4. Добавление правила для конкретного сценария:
   sudo semanage fcontext -a -t user_home_t "/opt/app(/.*)?"; 
   sudo restorecon -Rv /opt/app

Дополнительная информация: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/

EOF
}

# ============ SELinux Policy Management ============

SELINUX_MODE="unknown"
INSTALLED_APPS=()

check_selinux_status() {
    if [ ! -f /etc/selinux/config ]; then
        SELINUX_MODE="disabled"
        return 0
    fi
    
    if getenforce >/dev/null 2>&1; then
        SELINUX_MODE=$(getenforce)
        return 0
    fi
    
    SELINUX_MODE="unknown"
    return 0
}

add_selinux_policy_for_app() {
    local app_name="$1"
    local app_path="$2"
    
    if [ "$SELINUX_MODE" != "enforcing" ] && [ "$SELINUX_MODE" != "permissive" ]; then
        return 0
    fi
    
    if ! command -v semanage >/dev/null 2>&1; then
        return 0
    fi
    
    echo -e "${BLUE}Добавление SELinux политик для $app_name в $app_path${NC}"
    
    # Добавляем контекст для исполняемых файлов
    semanage fcontext -a -t user_home_t "$app_path(/.*)?" 2>/dev/null || true
    
    # Применяем контекст
    restorecon -Rv "$app_path" 2>/dev/null || true
}

apply_selinux_audit2allow() {
    if [ "$SELINUX_MODE" != "enforcing" ] && [ "$SELINUX_MODE" != "permissive" ]; then
        return 0
    fi
    
    if ! command -v audit2allow >/dev/null 2>&1; then
        return 0
    fi
    
    # Проверяем есть ли нарушения
    if audit2allow -a -C 2>/dev/null | grep -q "AVC"; then
        echo -e "${YELLOW}Обнаружены нарушения SELinux, создаю политики...${NC}"
        audit2allow -a -M redos_setup 2>/dev/null || true
        
        if [ -f redos_setup.pp ]; then
            semodule -i redos_setup.pp 2>/dev/null && echo -e "${GREEN}✓ Политики SELinux применены${NC}" || true
            rm -f redos_setup.pp redos_setup.mod 2>/dev/null || true
        fi
    fi
}

track_installed_app() {
    local app_name="$1"
    local app_path="$2"
    
    INSTALLED_APPS+=("$app_name:$app_path")
}

apply_policies_for_all_apps() {
    local i
    local app_name
    local app_path
    
    if [ "$SELINUX_MODE" = "disabled" ]; then
        return 0
    fi
    
    if [ ${#INSTALLED_APPS[@]} -eq 0 ]; then
        return 0
    fi
    
    echo -e "${BLUE}Применение SELinux политик для установленных приложений...${NC}"
    
    for i in "${!INSTALLED_APPS[@]}"; do
        IFS=':' read -r app_name app_path <<< "${INSTALLED_APPS[$i]}"
        add_selinux_policy_for_app "$app_name" "$app_path"
    done
    
    # Применяем политики из audit2allow если доступно
    apply_selinux_audit2allow
}

# Функция установки базовых репозиториев и системных пакетов
install_base_system() {
    echo -e "${GREEN}=== Установка базовых репозиториев и системных пакетов ===${NC}"
    
    # Обновление системы
    echo -e "${BLUE}Обновление системы...${NC}"
    dnf clean all
    dnf makecache
    dnf update -y
    check_success "Обновление системы"
    
    # Установка репозиториев
    echo -e "${BLUE}Установка репозиториев...${NC}"
    dnf install -y r7-release
    check_success "Установка репозитория r7"
    
    dnf install -y yandex-browser-release
    check_success "Установка репозитория Яндекс Браузера"
    
    # Установка MAX репозитория
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
    
    # Обновление кэша
    dnf makecache
    check_success "Обновление кэша репозиториев"
    
    # Установка ядра
    echo -e "${BLUE}Установка ядра...${NC}"
    dnf install -y redos-kernels6-release
    check_success "Установка ядра redos-kernels6"
    
    # Финальное обновление
    dnf update -y
    check_success "Финальное обновление"
    
    # Установка основных пакетов
    echo -e "${BLUE}Установка основных пакетов...${NC}"
    local base_packages="pavucontrol r7-office yandex-browser-stable sshfs pinta perl-Getopt-Long perl-File-Copy"
    dnf install -y $base_packages
    check_success "Установка основных пакетов"
    
    # Установка MAX
    dnf install -y max
    check_success "Установка MAX"
}

# Функция установки шрифтов Liberation (обновленная для .zip)
install_liberation_fonts() {
    if confirm_installation "шрифты Liberation"; then
        # Проверяем наличие unzip
        if ! command -v unzip &> /dev/null; then
            echo -e "${BLUE}Устанавливаю unzip...${NC}"
            dnf install -y unzip
            check_success "Установка unzip"
        fi
        
        # Пробуем скачать .zip (новый формат)
        if download_from_github "Liberation.zip" "$WORK_DIR"; then
            if [ -f "$WORK_DIR/Liberation.zip" ]; then
                cd "$WORK_DIR"
                
                # Создаем директорию для шрифтов
                mkdir -p /usr/share/fonts/liberation
                
                # Распаковываем архив
                echo -e "${BLUE}Распаковка Liberation.zip...${NC}"
                unzip -o Liberation.zip -d /usr/share/fonts/liberation/
                check_success "Распаковка архива Liberation.zip"
                rm -f Liberation.zip
                
                # Устанавливаем правильные права
                chmod 644 /usr/share/fonts/liberation/* 2>/dev/null
                
                # Обновляем кэш шрифтов
                echo -e "${BLUE}Обновление кэша шрифтов...${NC}"
                fc-cache -fv
                
                # Проверяем установку
                if fc-list | grep -i liberation > /dev/null; then
                    echo -e "${GREEN}✓ Шрифты Liberation успешно установлены${NC}"
                else
                    echo -e "${YELLOW}Шрифты установлены, но не обнаружены в кэше. Возможно, требуется перезагрузка.${NC}"
                fi
                
                check_success "Установка шрифтов Liberation"
            fi
        # Если .zip не найден, пробуем старый формат .tar.gz (обратная совместимость)
        elif download_from_github "Liberation.tar.gz" "$WORK_DIR"; then
            if [ -f "$WORK_DIR/Liberation.tar.gz" ]; then
                cd "$WORK_DIR"
                mkdir -p /usr/share/fonts/liberation
                tar -xzf Liberation.tar.gz
                cp Liberation/* /usr/share/fonts/liberation/
                rm -rf Liberation
                rm -f Liberation.tar.gz
                chmod 644 /usr/share/fonts/liberation/* 2>/dev/null
                fc-cache -fv
                check_success "Установка шрифтов Liberation (старый формат)"
            fi
        else
            echo -e "${RED}✗ Файл со шрифтами Liberation не найден в релизе${NC}"
        fi
    fi
}

# Функция выбора версии ViPNet
vipnet_client_asset() {
    if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        echo "vipnetclient-gui_gost_x86-64_5.1.3-8402.rpm"
    else
        echo "vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
    fi
}

select_vipnet_version() {
    if ! is_component_supported "vipnet"; then
        warn_component_not_supported "установку ViPNet"
        return 0
    fi

    echo -e "${GREEN}=== Выбор версии ViPNet ===${NC}" >&2
    echo "1. ViPNet Client (без деловой почты)" >&2
    echo "2. ViPNet + Деловая почта (DP)" >&2
    local choice=$(read_from_terminal "${YELLOW}Выберите вариант (1 или 2):${NC}")
    
    case $choice in
        1)
            local client_asset
            client_asset=$(vipnet_client_asset)
            echo -e "${BLUE}Установка ViPNet Client...${NC}"
            download_from_github "$client_asset" "$WORK_DIR"
            if [ -f "$WORK_DIR/$client_asset" ]; then
                dnf install -y "$WORK_DIR/$client_asset"
                check_success "Установка ViPNet Client"
                rm -f "$WORK_DIR/$client_asset"
            else
                echo -e "${RED}✗ Ошибка загрузки ViPNet Client${NC}"
                return 1
            fi
            ;;
        2)
            echo -e "${BLUE}Установка ViPNet + Деловая почта...${NC}"
            if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
                local client_asset
                client_asset=$(vipnet_client_asset)
                download_from_github "$client_asset" "$WORK_DIR"
                download_from_github "vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm" "$WORK_DIR"
                if [ -f "$WORK_DIR/$client_asset" ] && [ -f "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm" ]; then
                    dnf install -y "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
                    check_success "Установка ViPNet + Деловая почта"
                    rm -f "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
                else
                    echo -e "${RED}✗ Ошибка загрузки пакетов ViPNet для РЕД ОС 8+${NC}"
                    return 1
                fi
            else
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
            track_installed_app "Telegram" "/opt/telegram"
            rm -rf Telegram
            rm -f tsetup.tar.xz
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
    if ! is_component_supported "cryptopro"; then
        warn_component_not_supported "установку КриптоПро"
        return 0
    fi

    if confirm_installation "инструкцию по установке КриптоПро"; then
        echo -e "${YELLOW}Автоматическая установка КриптоПро из release отключена.${NC}"
        echo -e "${BLUE}Рекомендуется устанавливать КриптоПро через https://install.kontur.ru${NC}"
        echo -e "${BLUE}Кратко: откройте сайт, выберите установку для вашей версии РЕД ОС и выполните шаги мастера Контур.${NC}"
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
                # Отслеживаем установку 1С
                [ -d /opt/1C ] && track_installed_app "1C:Enterprise" "/opt/1C"
                [ -d /usr/lib1cv8 ] && track_installed_app "1C:Enterprise" "/usr/lib1cv8"
                echo -e "${GREEN}✓ 1С успешно установлена${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Пропускаем установку 1С${NC}"
    fi
}

# Функция настройки TRIM для SSD
setup_trim() {
    if confirm_installation "настройку TRIM для SSD"; then
        echo -e "${BLUE}Настройка TRIM для SSD...${NC}"
        systemctl enable --now fstrim.timer
        check_success "Настройка TRIM"
    else
        echo -e "${YELLOW}Пропускаем настройку TRIM${NC}"
    fi
}

# Функция обновления GRUB
update_grub() {
    if confirm_installation "обновление конфигурации GRUB"; then
        echo -e "${BLUE}Обновление GRUB...${NC}"
        grub2-mkconfig -o /boot/grub2/grub.cfg
        check_success "Обновление GRUB"
    else
        echo -e "${YELLOW}Пропускаем обновление GRUB${NC}"
    fi
}

# Функция настройки моноблока KSG
setup_ksg() {
    if confirm_installation "настройку для моноблока KSG"; then
        echo -e "${BLUE}Настройка моноблока KSG...${NC}"
        if [ -f "/etc/gdm/Init/Default" ]; then
            insert_before_exit "/etc/gdm/Init/Default" "xrandr --output HDMI-3 --primary"
            echo -e "${GREEN}✓ Настройка KSG выполнена (команда добавлена перед exit 0)${NC}"
        else
            echo -e "${RED}✗ Файл /etc/gdm/Init/Default не найден${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем настройку KSG${NC}"
    fi
}

# === НАЧАЛО СКРИПТА ===

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Этот скрипт должен запускаться с правами root${NC}" 
   exit 1
fi

# Проверка, что /dev/tty доступен
if [ ! -e /dev/tty ]; then
    echo -e "${RED}Ошибка: /dev/tty не доступен. Запустите скрипт в интерактивном терминале.${NC}"
    exit 1
fi

# Определение версии ОС и совместимости компонентов
detect_os_version

echo -e "${GREEN}=== Начало настройки РЕД ОС ===${NC}"
echo -e "${BLUE}Дата запуска: $(date)${NC}"
echo -e "${BLUE}GitHub: https://github.com/$GITHUB_USER/$GITHUB_REPO${NC}"
echo -e "${BLUE}Packages release: $ASSETS_RELEASE_TAG${NC}"
show_os_compatibility_info
echo ""

# Управление SELinux
handle_selinux

# Проверка текущего статуса SELinux
check_selinux_status

# Настройка DNF
if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf 2>/dev/null; then
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

# === УСТАНОВКА БАЗОВОЙ СИСТЕМЫ ===
if confirm_installation "базовую систему (репозитории, ядро, r7-office, Яндекс.Браузер, MAX, системные утилиты)"; then
    install_base_system
else
    echo -e "${YELLOW}Пропускаем установку базовой системы${NC}"
fi

# === ВЫБОР ДОПОЛНИТЕЛЬНЫХ ПРОГРАММ ===
echo -e "${GREEN}=== Выбор дополнительных программ для установки ===${NC}"
echo -e "${YELLOW}Будут загружены только те программы, на которые вы дадите согласие${NC}"
echo ""

# Шрифты
install_liberation_fonts

# Браузеры
install_chromium_gost

# Мессенджеры
install_messengers

# Kaspersky Agent
install_kaspersky

# КриптоПро
install_cryptopro

# ViPNet (с выбором версии)
if is_component_supported "vipnet" && confirm_installation "ViPNet"; then
    select_vipnet_version
elif ! is_component_supported "vipnet"; then
    warn_component_not_supported "установку ViPNet"
else
    echo -e "${YELLOW}Пропускаем установку ViPNet${NC}"
fi

# 1С
install_1c

# === СИСТЕМНЫЕ НАСТРОЙКИ ===
echo -e "${GREEN}=== Системные настройки ===${NC}"

# Настройка TRIM
setup_trim

# Обновление GRUB
update_grub

# Настройка для моноблока KSG
setup_ksg

# Применение SELinux политик для установленных приложений
apply_policies_for_all_apps

# === ЗАВЕРШЕНИЕ ===
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo -e "${BLUE}Время завершения: $(date)${NC}"
echo ""

# Вывод списка установленных программ
echo -e "${GREEN}Установленные компоненты:${NC}"
command -v chromium-gost >/dev/null 2>&1 && echo "  ✓ Chromium-GOST"
command -v sreda >/dev/null 2>&1 && echo "  ✓ СРЕДА"
command -v vk-messenger >/dev/null 2>&1 && echo "  ✓ VK Messenger"
command -v telegram >/dev/null 2>&1 && echo "  ✓ Telegram"
[ -d /usr/share/fonts/liberation ] && echo "  ✓ Шрифты Liberation"
[ -d /opt/kaspersky ] 2>/dev/null && echo "  ✓ Kaspersky Agent"
[ -d /opt/cprocsp ] 2>/dev/null && echo "  ✓ КриптоПро"
[ -f /etc/vipnet.conf ] && echo "  ✓ ViPNet"
[ -d /opt/1cv8 ] 2>/dev/null && echo "  ✓ 1С:Предприятие"
command -v r7-office >/dev/null 2>&1 && echo "  ✓ R7 Office"
command -v yandex-browser >/dev/null 2>&1 && echo "  ✓ Яндекс.Браузер"
command -v pavucontrol >/dev/null 2>&1 && echo "  ✓ Pavucontrol (звук)"
command -v sshfs >/dev/null 2>&1 && echo "  ✓ SSHFS"
command -v pinta >/dev/null 2>&1 && echo "  ✓ Pinta"

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ВНИМАНИЕ! Для корректной работы некоторых программ${NC}"
echo -e "${YELLOW}  (ViPNet, КриптоПро, 1С) рекомендуется перезагрузить систему.${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Запрос на перезагрузку
answer=$(read_from_terminal "${YELLOW}Перезагрузить систему сейчас? (y/n)${NC}")
if [[ $answer =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Перезагрузка через 5 секунд...${NC}"
    sleep 5
    sync
    reboot
else
    echo -e "${GREEN}Перезагрузка отменена. Вы можете перезагрузить систему позже командой:${NC}"
    echo -e "${BLUE}  sudo reboot${NC}"
fi





