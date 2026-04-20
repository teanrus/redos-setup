#!/bin/bash
##############################################################################
# setup_cli.sh — CLI-интерфейс для настройки РЕД ОС
#
# Описание:
#   Командная строка для автоматизированной настройки РЕД ОС.
#   Предоставляет интерфейс командной строки для установки компонентов,
#   управления конфигурацией и выполнения задач настройки системы.
#
# Использование:
#   ./setup_cli.sh [опции] [команды]
#
# Опции:
#   -h, --help          Показать справку
#   -v, --version       Показать версию
#   --dry-run           Симуляция выполнения без изменений
#
# Зависимости: bash, dnf, curl, wget, coreutils
# Опционально: unzip, rpm, tar
##############################################################################

set -euo pipefail

# ------------------------------
# 1. Metadata and globals
# ------------------------------

SCRIPT_VERSION="2.9.0"
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
ASSETS_RELEASE_TAG="${ASSETS_RELEASE_TAG:-packages}"

DEFAULT_WORK_DIR="/home/inst"
WORK_DIR="$DEFAULT_WORK_DIR"

COMMAND=""
TARGET_COMPONENT=""
TARGET_VARIANT=""

NON_INTERACTIVE=0
DRY_RUN=0
VERBOSE=0
NO_COLOR=0
FORCE=0
OUTPUT_JSON=0
DIRECT_INSTALL_MODE=0

OS_NAME="Unknown OS"
OS_VERSION_ID="unknown"
OS_MAJOR_VERSION=""
IS_REDOS=0

CRYPTOPRO_SUPPORTED=0
VIPNET_SUPPORTED=0

SELINUX_MODE="unknown"
MANAGE_SELINUX_POLICIES=0
INSTALLED_APPS=()

EXIT_OK=0
EXIT_ERROR=1
EXIT_USAGE=2
EXIT_ROOT_REQUIRED=3
EXIT_OS_UNSUPPORTED=4
EXIT_COMPONENT_UNSUPPORTED=5
EXIT_MISSING_DEPENDENCY=6
EXIT_DOWNLOAD_FAILED=7

# ------------------------------
# 2. Colors and output helpers
# ------------------------------

init_colors() {
    if [ "$NO_COLOR" -eq 1 ] || [ ! -t 1 ]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        NC=''
        return
    fi

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
}

log_info() {
    echo -e "${BLUE}$*${NC}"
}

log_success() {
    echo -e "${GREEN}$*${NC}"
}

log_warn() {
    echo -e "${YELLOW}$*${NC}"
}

log_error() {
    echo -e "${RED}$*${NC}" >&2
}

log_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${BLUE}[verbose] $*${NC}"
    fi
}

die() {
    local message="$1"
    local code="${2:-$EXIT_ERROR}"
    log_error "$message"
    exit "$code"
}

# ------------------------------
# 3. Core utility helpers
# ------------------------------

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] $*"
        return 0
    fi

    "$@"
}

read_from_terminal() {
    local prompt="$1"
    local answer

    echo -e "$prompt" >&2
    read -r answer < /dev/tty 2>/dev/null || true
    echo "$answer"
}

confirm_installation() {
    local component_label="$1"

    if [ "$NON_INTERACTIVE" -eq 1 ] || [ "$DIRECT_INSTALL_MODE" -eq 1 ]; then
        return 0
    fi

    local answer
    answer=$(read_from_terminal "${YELLOW}Установить $component_label? (y/n)${NC}")
    [[ "$answer" =~ ^[Yy]$ ]]
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Этот скрипт должен запускаться с правами root" "$EXIT_ROOT_REQUIRED"
    fi
}

require_tty_if_needed() {
    if [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DIRECT_INSTALL_MODE" -eq 0 ] && [ ! -e /dev/tty ]; then
        die "Ошибка: /dev/tty не доступен. Запустите скрипт в интерактивном терминале." "$EXIT_ERROR"
    fi
}

check_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_info "Устанавливаю $cmd..."
        run_cmd dnf install -y "$cmd"
        [ $? -eq 0 ] || die "Ошибка установки $cmd" "$EXIT_MISSING_DEPENDENCY"
    fi
}

ensure_workdir() {
    run_cmd mkdir -p "$WORK_DIR" || die "Не удалось создать рабочую директорию: $WORK_DIR"
    run_cmd chmod 755 "$WORK_DIR" || die "Не удалось установить права для $WORK_DIR"
    cd "$WORK_DIR" || die "Не удалось перейти в рабочую директорию: $WORK_DIR"
}

get_release_asset_url() {
    local release_tag="$1"
    local file_name="$2"
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$release_tag/$file_name"
}

get_latest_release_url() {
    local file_name="$1"
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$file_name"
}

get_assets_release_url() {
    local file_name="$1"
    get_release_asset_url "$ASSETS_RELEASE_TAG" "$file_name"
}

download_from_github() {
    local file_name="$1"
    local dest_dir="$2"
    local url

    url=$(get_assets_release_url "$file_name")
    log_info "Загрузка $file_name..."

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] wget --progress=bar:force -O \"$dest_dir/$file_name\" \"$url\""
        return 0
    fi

    if ! curl -s --head -f "$url" >/dev/null 2>&1; then
        log_error "✗ Файл $file_name не найден в release '$ASSETS_RELEASE_TAG'"
        return "$EXIT_DOWNLOAD_FAILED"
    fi

    if wget --progress=bar:force -O "$dest_dir/$file_name" "$url" 2>&1; then
        log_success "✓ $file_name успешно загружен"
        return 0
    fi

    log_error "✗ Ошибка загрузки $file_name"
    return "$EXIT_DOWNLOAD_FAILED"
}

prepare_runtime() {
    require_root
    require_tty_if_needed
    ensure_workdir
    check_command "curl"
    check_command "wget"
}

prepare_system_defaults() {
    disable_selinux_if_needed
    configure_dnf
}

# ------------------------------
# 4. OS detection and compatibility
# ------------------------------

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

show_os_compatibility_info() {
    if [ "$OUTPUT_JSON" -eq 1 ]; then
        cat << EOF
{"os_name":"$OS_NAME","os_version_id":"$OS_VERSION_ID","os_major_version":"$OS_MAJOR_VERSION","is_redos":$IS_REDOS,"cryptopro_supported":$CRYPTOPRO_SUPPORTED,"vipnet_supported":$VIPNET_SUPPORTED}
EOF
        return
    fi

    log_info "Обнаружена ОС: $OS_NAME"

    if [ "$IS_REDOS" -ne 1 ]; then
        log_warn "Скрипт разработан для РЕД ОС. Текущая ОС не распознана как РЕД ОС."
        return
    fi

    if [ -n "$OS_MAJOR_VERSION" ]; then
        log_info "Основная версия РЕД ОС: $OS_MAJOR_VERSION"
    fi

    if [ "$OS_MAJOR_VERSION" = "7" ]; then
        log_success "Режим совместимости: поддерживается полный сценарий установки, ViPNet ставится из пакетов для РЕД ОС 7.x."
    elif [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        log_warn "Для РЕД ОС $OS_VERSION_ID ViPNet будет устанавливаться из пакетов для РЕД ОС 8+."
    else
        log_warn "Не удалось однозначно определить версию РЕД ОС. Несовместимые компоненты будут заблокированы."
    fi
}

is_os_supported() {
    [ "$IS_REDOS" -eq 1 ]
}

is_component_supported() {
    local component_name="$1"

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

component_support_reason() {
    local component_name="$1"

    case "$component_name" in
        cryptopro|vipnet)
            if [ "$IS_REDOS" -ne 1 ]; then
                echo "компонент поддерживается только на РЕД ОС, а текущая ОС не распознана как РЕД ОС"
            elif [ -z "$OS_MAJOR_VERSION" ]; then
                echo "не удалось определить основную версию РЕД ОС"
            else
                echo "компонент недоступен для текущей версии ОС"
            fi
            ;;
        *)
            echo "компонент поддерживается"
            ;;
    esac
}

warn_component_not_supported() {
    local component_name="$1"
    log_warn "Пропускаем $(component_label "$component_name"): $(component_support_reason "$component_name")"
}

# ------------------------------
# 5. Environment checks / doctor
# ------------------------------

doctor_root() {
    if [[ $EUID -eq 0 ]]; then
        log_success "root: ok"
    else
        log_warn "root: скрипт запущен без прав root"
    fi
}

doctor_tty() {
    if [ -e /dev/tty ]; then
        log_success "/dev/tty: ok"
    else
        log_warn "/dev/tty: недоступен"
    fi
}

doctor_required_commands() {
    local cmd
    for cmd in bash curl wget dnf; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "$cmd: ok"
        else
            log_warn "$cmd: не найден"
        fi
    done
}

doctor_network() {
    if curl -s --head -f "https://github.com" >/dev/null 2>&1; then
        log_success "network/github: ok"
    else
        log_warn "network/github: недоступно"
    fi
}

doctor_release_urls() {
    local url
    url=$(get_latest_release_url "setup.sh")

    if curl -s --head -f "$url" >/dev/null 2>&1; then
        log_success "release asset setup.sh: ok"
    else
        log_warn "release asset setup.sh: не найден"
    fi
}

cmd_doctor() {
    detect_os_version
    show_os_compatibility_info
    doctor_root
    doctor_tty
    doctor_required_commands
    doctor_network
    doctor_release_urls
}

# ------------------------------
# 6. Low-level system actions
# ------------------------------

disable_selinux_if_needed() {
    if [ ! -f /etc/selinux/config ]; then
        return 0
    fi

    local selinux_current=$(grep '^SELINUX=' /etc/selinux/config 2>/dev/null | cut -d= -f2)
    
    # Если SELinux отключен, предлагаем его включить
    if [ "$selinux_current" = "disabled" ]; then
        log_warn "Обнаружен SELinux в режиме disabled (отключен)"
        
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            # В неинтерактивном режиме оставляем как есть
            log_info "SELinux остаётся отключен (неинтерактивный режим)"
            return 0
        else
            # В интерактивном режиме спрашиваем пользователя
            echo -e "${YELLOW}=== Включение SELinux ===${NC}"
            echo "SELinux в настоящее время отключен (disabled). Рекомендуется его включить для безопасности."
            echo "Доступные варианты:"
            echo "1. Включить SELinux в режиме enforcing (самый безопасный)"
            echo "2. Включить SELinux в режиме permissive (логирует нарушения, но не блокирует)"
            echo "3. Оставить SELinux отключенным (disabled)"
            local choice
            choice=$(read_from_terminal "${YELLOW}Выберите вариант (1, 2 или 3):${NC}")
            
            case "$choice" in
                1)
                    _set_selinux_enforcing
                    ;;
                2)
                    _set_selinux_permissive_from_disabled
                    ;;
                3)
                    log_info "SELinux остаётся отключенным."
                    ;;
                *)
                    log_warn "Неверный выбор. SELinux остаётся без изменений."
                    ;;
            esac
        fi
    elif [ "$selinux_current" = "enforcing" ]; then
        log_warn "Обнаружен SELinux в режиме enforcing"
        
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            # В неинтерактивном режиме выбираем режим permissive (более безопасно)
            log_info "Переведение SELinux в режим permissive (неинтерактивный режим)..."
            _set_selinux_permissive
        else
            # В интерактивном режиме спрашиваем пользователя
            echo -e "${YELLOW}=== Настройка SELinux ===${NC}"
            echo "SELinux в настоящее время активирован (enforcing). Доступные варианты:"
            echo "1. Оставить SELinux в режиме enforcing (самый безопасный, но может потребоваться добавление правил)"
            echo "2. Перевести SELinux в режим permissive (логирует нарушения, но не блокирует)"
            echo "3. Отключить SELinux полностью (disabled) - НЕ рекомендуется"
            local choice
            choice=$(read_from_terminal "${YELLOW}Выберите вариант (1, 2 или 3):${NC}")
            
            case "$choice" in
                1)
                    log_info "SELinux остаётся в режиме enforcing. Рекомендуется использовать 'semanage' для добавления необходимых правил."
                    _print_selinux_help
                    ;;
                2)
                    _set_selinux_permissive
                    ;;
                3)
                    _set_selinux_disabled
                    ;;
                *)
                    log_warn "Неверный выбор. SELinux остаётся без изменений."
                    ;;
            esac
        fi
    fi
}

_set_selinux_permissive() {
    log_info "Переведение SELinux в режим permissive..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config"
        return 0
    fi
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || die "Ошибка переведения SELinux в permissive"
    log_success "✓ SELinux переведён в режим permissive"
    log_info "Требуется перезагрузка для применения изменений. Используйте: sudo reboot"
}

_set_selinux_disabled() {
    log_warn "Отключение SELinux..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config"
        return 0
    fi
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config || die "Ошибка отключения SELinux"
    log_success "✓ SELinux отключен (disabled)"
    log_info "Требуется перезагрузка для полного применения изменений. Используйте: sudo reboot"
}

_set_selinux_enforcing() {
    log_info "Включение SELinux в режим enforcing..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config"
        return 0
    fi
    sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config || die "Ошибка включения SELinux в enforcing"
    log_success "✓ SELinux включен в режим enforcing"
    log_warn "Требуется перезагрузка для применения изменений. Используйте: sudo reboot"
    log_info "После перезагрузки система будет работать с SELinux в режиме enforcing (рекомендуется использовать semanage для добавления необходимых правил)"
    _print_selinux_help
}

_set_selinux_permissive_from_disabled() {
    log_info "Включение SELinux в режим permissive..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] sed -i 's/SELINUX=disabled/SELINUX=permissive/' /etc/selinux/config"
        return 0
    fi
    sed -i 's/SELINUX=disabled/SELINUX=permissive/' /etc/selinux/config || die "Ошибка включения SELinux в permissive"
    log_success "✓ SELinux включен в режим permissive"
    log_info "Требуется перезагрузка для применения изменений. Используйте: sudo reboot"
    log_info "В режиме permissive SELinux логирует нарушения, но не блокирует приложения"
}

_print_selinux_help() {
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
        log_verbose "SELinux не активирован, пропускаю добавление политик для $app_name"
        return 0
    fi
    
    if [ ! -x "semanage" ]; then
        log_verbose "semanage не установлен, пропускаю добавление политик"
        return 0
    fi
    
    log_verbose "Добавление SELinux политик для $app_name в $app_path"
    
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] semanage fcontext -a -t user_home_t \"$app_path(/.*)?\""
        echo "[dry-run] restorecon -Rv $app_path"
        return 0
    fi
    
    # Добавляем контекст для исполняемых файлов
    semanage fcontext -a -t user_home_t "$app_path(/.*)?" 2>/dev/null || true
    
    # Применяем контекст
    restorecon -Rv "$app_path" 2>/dev/null || true
}

apply_selinux_audit2allow() {
    if [ "$SELINUX_MODE" != "enforcing" ] && [ "$SELINUX_MODE" != "permissive" ]; then
        log_verbose "SELinux не активирован, пропускаю применение политик"
        return 0
    fi
    
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] audit2allow -l -a"
        return 0
    fi
    
    if ! command -v audit2allow >/dev/null 2>&1; then
        log_verbose "audit2allow не установлен"
        return 0
    fi
    
    log_verbose "Применение SELinux политик из audit2allow..."
    
    # Проверяем есть ли нарушения
    if audit2allow -a -C 2>/dev/null | grep -q "AVC"; then
        log_info "Обнаружены нарушения SELinux, создаю политики..."
        audit2allow -a -M redos_setup 2>/dev/null || true
        
        if [ -f redos_setup.pp ]; then
            semodule -i redos_setup.pp 2>/dev/null && log_success "✓ Политики SELinux применены" || true
            rm -f redos_setup.pp redos_setup.mod 2>/dev/null || true
        fi
    else
        log_verbose "Нарушений SELinux не обнаружено"
    fi
}

track_installed_app() {
    local app_name="$1"
    local app_path="$2"
    
    INSTALLED_APPS+=("$app_name:$app_path")
    log_verbose "Отслеживаю приложение: $app_name в $app_path"
}

apply_policies_for_all_apps() {
    local i
    local app_name
    local app_path
    
    if [ "$SELINUX_MODE" = "disabled" ]; then
        log_verbose "SELinux отключен, политики не применяются"
        return 0
    fi
    
    if [ ${#INSTALLED_APPS[@]} -eq 0 ]; then
        log_verbose "Нет отслеживаемых приложений"
        return 0
    fi
    
    log_info "Применение SELinux политик для установленных приложений..."
    
    for i in "${!INSTALLED_APPS[@]}"; do
        IFS=':' read -r app_name app_path <<< "${INSTALLED_APPS[$i]}"
        add_selinux_policy_for_app "$app_name" "$app_path"
    done
    
    # Применяем политики из audit2allow если доступно
    apply_selinux_audit2allow
}

configure_dnf() {
    if grep -q "max_parallel_downloads" /etc/dnf/dnf.conf 2>/dev/null; then
        return 0
    fi

    log_info "Настройка DNF..."
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] echo 'max_parallel_downloads=10' >> /etc/dnf/dnf.conf"
        return 0
    fi

    echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf || die "Ошибка настройки DNF"
    log_success "✓ DNF настроен"
}

insert_before_exit() {
    local file="$1"
    local line="$2"
    local temp_file

    if [ ! -f "$file" ]; then
        die "Файл $file не найден"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] insert line before exit 0 in $file: $line"
        return 0
    fi

    temp_file=$(mktemp) || die "Не удалось создать временный файл"

    while IFS= read -r file_line; do
        if [[ "$file_line" =~ ^[[:space:]]*exit[[:space:]]+0 ]]; then
            echo "$line" >> "$temp_file"
        fi
        echo "$file_line" >> "$temp_file"
    done < "$file"

    mv "$temp_file" "$file" || die "Не удалось обновить $file"
    chmod --reference="$file" "$file" 2>/dev/null || chmod 755 "$file"
}

write_max_repo() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] write /etc/yum.repos.d/max.repo"
        return 0
    fi

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
}

# ------------------------------
# 7. Installers: base system
# ------------------------------

install_base_system() {
    confirm_installation "$(component_label base)" || return 0

    log_info "=== Установка базовой системы ==="

    run_cmd dnf clean all || die "Ошибка очистки кэша DNF"
    run_cmd dnf makecache || die "Ошибка обновления кэша DNF"
    run_cmd dnf update -y || die "Ошибка обновления системы"

    run_cmd dnf install -y r7-release || die "Ошибка установки r7-release"
    run_cmd dnf install -y yandex-browser-release || die "Ошибка установки yandex-browser-release"

    write_max_repo || die "Ошибка создания репозитория MAX"
    run_cmd rpm --import https://download.max.ru/linux/rpm/public.asc || die "Ошибка импорта ключа MAX"

    run_cmd dnf makecache || die "Ошибка обновления кэша репозиториев"
    run_cmd dnf install -y redos-kernels6-release || die "Ошибка установки redos-kernels6-release"
    run_cmd dnf update -y || die "Ошибка финального обновления"

    run_cmd dnf install -y pavucontrol r7-office yandex-browser-stable sshfs pinta perl-Getopt-Long perl-File-Copy || die "Ошибка установки базовых пакетов"
    run_cmd dnf install -y max || die "Ошибка установки MAX"

    log_success "✓ Базовая система установлена"
}

# ------------------------------
# 8. Installers: optional apps
# ------------------------------

install_liberation_fonts() {
    confirm_installation "$(component_label liberation-fonts)" || return 0

    if ! command -v unzip >/dev/null 2>&1; then
        run_cmd dnf install -y unzip || die "Ошибка установки unzip"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будут установлены шрифты Liberation в /usr/share/fonts/liberation"
        return 0
    fi

    if download_from_github "Liberation.zip" "$WORK_DIR"; then
        mkdir -p /usr/share/fonts/liberation || die "Ошибка создания каталога шрифтов"
        unzip -o "$WORK_DIR/Liberation.zip" -d /usr/share/fonts/liberation/ || die "Ошибка распаковки Liberation.zip"
        rm -f "$WORK_DIR/Liberation.zip"
        chmod 644 /usr/share/fonts/liberation/* 2>/dev/null
        fc-cache -fv || die "Ошибка обновления кэша шрифтов"
    elif download_from_github "Liberation.tar.gz" "$WORK_DIR"; then
        mkdir -p /usr/share/fonts/liberation || die "Ошибка создания каталога шрифтов"
        cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
        tar -xzf Liberation.tar.gz || die "Ошибка распаковки Liberation.tar.gz"
        cp Liberation/* /usr/share/fonts/liberation/ || die "Ошибка копирования Liberation"
        rm -rf Liberation Liberation.tar.gz
        chmod 644 /usr/share/fonts/liberation/* 2>/dev/null
        fc-cache -fv || die "Ошибка обновления кэша шрифтов"
    else
        die "Файл со шрифтами Liberation не найден в релизе" "$EXIT_DOWNLOAD_FAILED"
    fi

    log_success "✓ Шрифты Liberation установлены"
}

install_chromium_gost() {
    confirm_installation "$(component_label chromium-gost)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен Chromium-GOST"
        return 0
    fi

    download_from_github "chromium-gost-139.0.7258.139-linux-amd64.rpm" "$WORK_DIR" || die "Ошибка загрузки Chromium-GOST" "$EXIT_DOWNLOAD_FAILED"
    run_cmd dnf install -y "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm" || die "Ошибка установки Chromium-GOST"
    rm -f "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
    log_success "✓ Chromium-GOST установлен"
}

install_sreda() {
    confirm_installation "$(component_label sreda)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен мессенджер СРЕДА"
        return 0
    fi

    download_from_github "sreda.rpm" "$WORK_DIR" || die "Ошибка загрузки СРЕДА" "$EXIT_DOWNLOAD_FAILED"
    run_cmd dnf install -y "$WORK_DIR/sreda.rpm" || die "Ошибка установки СРЕДА"
    rm -f "$WORK_DIR/sreda.rpm"
    log_success "✓ СРЕДА установлена"
}

install_vk_messenger() {
    confirm_installation "$(component_label vk-messenger)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен VK Messenger"
        return 0
    fi

    download_from_github "vk-messenger.rpm" "$WORK_DIR" || die "Ошибка загрузки VK Messenger" "$EXIT_DOWNLOAD_FAILED"
    run_cmd dnf install -y "$WORK_DIR/vk-messenger.rpm" || die "Ошибка установки VK Messenger"
    rm -f "$WORK_DIR/vk-messenger.rpm"
    log_success "✓ VK Messenger установлен"
}

write_telegram_desktop_file() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] write /usr/share/applications/telegram.desktop"
        return 0
    fi

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
}

install_telegram() {
    confirm_installation "$(component_label telegram)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен Telegram в /opt/telegram"
        return 0
    fi

    download_from_github "tsetup.tar.xz" "$WORK_DIR" || die "Ошибка загрузки Telegram" "$EXIT_DOWNLOAD_FAILED"
    cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
    tar -xJf tsetup.tar.xz || die "Ошибка распаковки Telegram"
    mkdir -p /opt/telegram || die "Ошибка создания /opt/telegram"
    cp -r Telegram/* /opt/telegram/ || die "Ошибка копирования Telegram"
    ln -sf /opt/telegram/Telegram /usr/bin/telegram || die "Ошибка создания ссылки telegram"
    write_telegram_desktop_file || die "Ошибка создания telegram.desktop"
    chmod +x /usr/share/applications/telegram.desktop || die "Ошибка chmod для telegram.desktop"
    rm -rf Telegram
    rm -f tsetup.tar.xz
    track_installed_app "Telegram" "/opt/telegram"
    log_success "✓ Telegram установлен"
}

install_messengers_group() {
    install_sreda
    install_vk_messenger
    install_telegram
}

install_kaspersky() {
    confirm_installation "$(component_label kaspersky)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен Kaspersky Agent"
        return 0
    fi

    download_from_github "kasp.tar.gz" "$WORK_DIR" || die "Ошибка загрузки Kaspersky Agent" "$EXIT_DOWNLOAD_FAILED"
    cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
    tar -xzf kasp.tar.gz || die "Ошибка распаковки kasp.tar.gz"
    local script
    for script in ./*.sh; do
        [ -f "$script" ] || continue
        chmod +x "$script"
        "$script" || die "Ошибка запуска $script"
    done
    rm -f kasp.tar.gz ./*.sh
    log_success "✓ Kaspersky Agent установлен"
}

vipnet_client_asset() {
    if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        echo "vipnetclient-gui_gost_x86-64_5.1.3-8402.rpm"
    else
        echo "vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
    fi
}

install_vipnet_client() {
    local client_asset
    client_asset=$(vipnet_client_asset)

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлен ViPNet Client из пакета $client_asset"
        return 0
    fi

    download_from_github "$client_asset" "$WORK_DIR" || die "Ошибка загрузки ViPNet Client" "$EXIT_DOWNLOAD_FAILED"
    run_cmd dnf install -y "$WORK_DIR/$client_asset" || die "Ошибка установки ViPNet Client"
    rm -f "$WORK_DIR/$client_asset"
    log_success "✓ ViPNet Client установлен"
}

install_vipnet_dp() {
    local client_asset
    client_asset=$(vipnet_client_asset)

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
            log_info "Будут установлены ViPNet Client и Деловая почта для РЕД ОС 8+"
        else
            log_info "Будет установлен ViPNet + Деловая почта"
        fi
        return 0
    fi

    if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        download_from_github "$client_asset" "$WORK_DIR" || die "Ошибка загрузки ViPNet Client" "$EXIT_DOWNLOAD_FAILED"
        download_from_github "vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm" "$WORK_DIR" || die "Ошибка загрузки Деловой почты ViPNet" "$EXIT_DOWNLOAD_FAILED"
        run_cmd dnf install -y "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm" || die "Ошибка установки ViPNet для РЕД ОС 8+"
        rm -f "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
    else
        download_from_github "VipNet-DP.tar.gz" "$WORK_DIR" || die "Ошибка загрузки ViPNet-DP" "$EXIT_DOWNLOAD_FAILED"
        cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
        tar -xzf VipNet-DP.tar.gz || die "Ошибка распаковки ViPNet-DP.tar.gz"
        cd VipNet-DP || die "Не удалось перейти в каталог VipNet-DP"
        local rpm
        for rpm in ./*.rpm; do
            [ -f "$rpm" ] || continue
            run_cmd dnf install -y "$rpm" || die "Ошибка установки ViPNet RPM: $rpm"
        done
        cd "$WORK_DIR" || die "Не удалось вернуться в $WORK_DIR"
        rm -rf VipNet-DP
        rm -f VipNet-DP.tar.gz
    fi

    log_success "✓ ViPNet + Деловая почта установлены"
}

install_vipnet() {
    if ! is_component_supported "vipnet"; then
        die "$(component_support_reason vipnet)" "$EXIT_COMPONENT_UNSUPPORTED"
    fi

    confirm_installation "$(component_label vipnet)" || return 0

    local variant="$TARGET_VARIANT"

    if [ -z "$variant" ] && [ "$NON_INTERACTIVE" -eq 0 ] && [ "$DIRECT_INSTALL_MODE" -eq 0 ]; then
        log_info "=== Выбор версии ViPNet ==="
        echo "1. ViPNet Client (без деловой почты)"
        echo "2. ViPNet + Деловая почта (DP)"
        variant=$(read_from_terminal "${YELLOW}Выберите вариант (1 или 2):${NC}")
        case "$variant" in
            1) variant="client" ;;
            2) variant="dp" ;;
            *) die "Неверный выбор варианта ViPNet" "$EXIT_USAGE" ;;
        esac
    fi

    if [ -z "$variant" ]; then
        variant="client"
    fi

    case "$variant" in
        client)
            install_vipnet_client
            ;;
        dp)
            install_vipnet_dp
            ;;
        *)
            die "Неизвестный вариант ViPNet: $variant" "$EXIT_USAGE"
            ;;
    esac
}

install_1c() {
    confirm_installation "$(component_label 1c)" || return 0

    if [ "$DRY_RUN" -eq 1 ]; then
        log_info "Будет установлена платформа 1С:Предприятие"
        return 0
    fi

    download_from_github "1c.tar.gz" "$WORK_DIR" || die "Ошибка загрузки 1С" "$EXIT_DOWNLOAD_FAILED"
    cd "$WORK_DIR" || die "Не удалось перейти в $WORK_DIR"
    tar -xzf 1c.tar.gz || die "Ошибка распаковки 1c.tar.gz"
    rm -f 1c.tar.gz

    if [ -d "lin_8_3_24_1691" ]; then
        cd lin_8_3_24_1691 || die "Не удалось перейти в lin_8_3_24_1691"
        chmod +x setup-full-8.3.24.1691-x86_64.run fix.sh || die "Ошибка chmod для 1С"
        ./setup-full-8.3.24.1691-x86_64.run || die "Ошибка запуска setup-full-8.3.24.1691-x86_64.run"
        ./fix.sh || die "Ошибка запуска fix.sh"
        cd "$WORK_DIR" || die "Не удалось вернуться в $WORK_DIR"
        rm -rf lin_8_3_24_1691
        # Отслеживаем установку 1С
        [ -d /opt/1C ] && track_installed_app "1C:Enterprise" "/opt/1C"
        [ -d /usr/lib1cv8 ] && track_installed_app "1C:Enterprise" "/usr/lib1cv8"
        log_success "✓ 1С установлена"
    else
        die "Каталог с файлами 1С не найден после распаковки"
    fi
}

# ------------------------------
# 9. Installers: system tweaks
# ------------------------------

setup_trim() {
    confirm_installation "$(component_label trim)" || return 0
    run_cmd systemctl enable --now fstrim.timer || die "Ошибка настройки TRIM"
    log_success "✓ TRIM настроен"
}

update_grub() {
    confirm_installation "$(component_label grub)" || return 0
    run_cmd grub2-mkconfig -o /boot/grub2/grub.cfg || die "Ошибка обновления GRUB"
    log_success "✓ GRUB обновлён"
}

setup_ksg() {
    confirm_installation "$(component_label ksg)" || return 0
    insert_before_exit "/etc/gdm/Init/Default" "xrandr --output HDMI-3 --primary"
    log_success "✓ Настройка KSG выполнена"
}

# ------------------------------
# 10. Component registry
# ------------------------------

component_exists() {
    local component="$1"
    case "$component" in
        base|liberation-fonts|chromium-gost|sreda|vk-messenger|telegram|messengers|kaspersky|cryptopro|vipnet|1c|trim|grub|ksg|all)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

component_label() {
    local component="$1"
    case "$component" in
        base) echo "базовую систему" ;;
        liberation-fonts) echo "шрифты Liberation" ;;
        chromium-gost) echo "Chromium-GOST" ;;
        sreda) echo "СРЕДА" ;;
        vk-messenger) echo "VK Messenger" ;;
        telegram) echo "Telegram" ;;
        messengers) echo "группу мессенджеров" ;;
        kaspersky) echo "Kaspersky Agent" ;;
        1c) echo "1С:Предприятие" ;;
        trim) echo "TRIM для SSD" ;;
        grub) echo "обновление GRUB" ;;
        ksg) echo "настройку для моноблока KSG" ;;
        all) echo "все совместимые компоненты" ;;
        *) echo "$component" ;;
    esac
}

component_group() {
    local component="$1"
    case "$component" in
        base) echo "base" ;;
        liberation-fonts|chromium-gost|sreda|vk-messenger|telegram|messengers|kaspersky|cryptopro|vipnet|1c) echo "apps" ;;
        trim|grub|ksg) echo "system" ;;
        all) echo "meta" ;;
        *) echo "unknown" ;;
    esac
}

component_requires_variant() {
    local component="$1"
    [ "$component" = "vipnet" ]
}

list_all_components() {
    cat << 'EOF'
base
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
messengers
kaspersky
cryptopro
vipnet
1c
trim
grub
ksg
all
EOF
}

run_component_install() {
    local component="$1"

    case "$component" in
        base) install_base_system ;;
        liberation-fonts) install_liberation_fonts ;;
        chromium-gost) install_chromium_gost ;;
        sreda) install_sreda ;;
        vk-messenger) install_vk_messenger ;;
        telegram) install_telegram ;;
        messengers) install_messengers_group ;;
        kaspersky) install_kaspersky ;;
        vipnet) install_vipnet ;;
        1c) install_1c ;;
        trim) setup_trim ;;
        grub) update_grub ;;
        ksg) setup_ksg ;;
        all) install_all_compatible ;;
        *) die "Неизвестный компонент: $component" "$EXIT_USAGE" ;;
    esac
}

install_all_compatible() {
    local component
    while IFS= read -r component; do
        [ "$component" = "all" ] && continue
        if is_component_supported "$component"; then
            run_component_install "$component"
        else
            warn_component_not_supported "$component"
        fi
    done << 'EOF'
base
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
kaspersky
cryptopro
vipnet
1c
trim
grub
ksg
EOF
}

# ------------------------------
# 11. Command handlers
# ------------------------------

cmd_help() {
    cat << 'EOF'
redos-setup - CLI для настройки рабочих мест на РЕД ОС

Usage:
  setup_cli.sh help
  setup_cli.sh version
  setup_cli.sh check-os
  setup_cli.sh list [--compatible]
  setup_cli.sh install <component> [options]
  setup_cli.sh doctor
  setup_cli.sh interactive

Commands:
  help
      Показать эту справку
  version
      Показать версию CLI
  check-os
      Определить ОС и показать совместимость
  list
      Показать компоненты
  install <component>
      Установить конкретный компонент или all
  doctor
      Выполнить базовую диагностику среды
  interactive
      Запустить интерактивный сценарий, близкий к текущему setup.sh

Components:
  base
  liberation-fonts
  chromium-gost
  sreda
  vk-messenger
  telegram
  messengers
  kaspersky
  cryptopro
  vipnet
  1c
  trim
  grub
  ksg
  all

Global options:
  -y, --yes            Не задавать вопросы подтверждения
  --dry-run            Только показать план действий
  --verbose            Подробный вывод
  --workdir PATH       Переопределить рабочую директорию
  --variant VALUE      Вариант ViPNet: client или dp
  --no-color           Отключить цветной вывод
  --force              Зарезервировано для будущих сценариев
  --json               JSON-вывод для check-os
EOF
}

cmd_version() {
    echo "redos-setup CLI $SCRIPT_VERSION"
}

cmd_check_os() {
    detect_os_version
    show_os_compatibility_info
}

cmd_list() {
    local compatible_only=0
    local component

    if [ "${REMAINING_ARGS[0]:-}" = "--compatible" ]; then
        compatible_only=1
    fi

    detect_os_version

    while IFS= read -r component; do
        if [ "$compatible_only" -eq 1 ] && ! is_component_supported "$component"; then
            continue
        fi

        printf '%-18s | %-10s | %s\n' \
            "$component" \
            "$(component_group "$component")" \
            "$(component_label "$component")"
    done << 'EOF'
base
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
messengers
kaspersky
cryptopro
vipnet
1c
trim
grub
ksg
all
EOF
}

cmd_install() {
    local component="$1"

    [ -n "$component" ] || die "Не указан компонент для install" "$EXIT_USAGE"
    component_exists "$component" || die "Неизвестный компонент: $component" "$EXIT_USAGE"

    detect_os_version
    check_selinux_status
    DIRECT_INSTALL_MODE=1

    prepare_runtime
    if [ "$component" = "base" ] || [ "$component" = "all" ]; then
        prepare_system_defaults
    fi

    if [ "$component" != "all" ] && ! is_component_supported "$component"; then
        die "$(component_support_reason "$component")" "$EXIT_COMPONENT_UNSUPPORTED"
    fi

    if component_requires_variant "$component" && [ -z "$TARGET_VARIANT" ] && [ "$NON_INTERACTIVE" -eq 1 ]; then
        TARGET_VARIANT="client"
    fi

    run_component_install "$component"
    
    # Применяем SELinux политики для установленных приложений
    apply_policies_for_all_apps
}

cmd_interactive() {
    detect_os_version
    check_selinux_status
    prepare_runtime
    prepare_system_defaults

    log_info "=== Начало интерактивной настройки РЕД ОС ==="
    log_info "Дата запуска: $(date)"
    log_info "GitHub: https://github.com/$GITHUB_USER/$GITHUB_REPO"
    log_info "Packages release: $ASSETS_RELEASE_TAG"
    show_os_compatibility_info
    echo ""

    install_base_system
    install_liberation_fonts
    install_chromium_gost
    install_messengers_group
    install_kaspersky
    if is_component_supported "vipnet"; then
        DIRECT_INSTALL_MODE=0
        install_vipnet
    else
        warn_component_not_supported "vipnet"
    fi
    install_1c
    setup_trim
    update_grub
    setup_ksg

    # Применяем SELinux политики для всех установленных приложений
    apply_policies_for_all_apps
    
    log_success "=== Настройка завершена ==="
}

# ------------------------------
# 12. Argument parsing
# ------------------------------

parse_global_args() {
    REMAINING_ARGS=()

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)
                NON_INTERACTIVE=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --json)
                OUTPUT_JSON=1
                shift
                ;;
            --workdir)
                [ $# -ge 2 ] || die "Для --workdir требуется путь" "$EXIT_USAGE"
                WORK_DIR="$2"
                shift 2
                ;;
            --variant)
                [ $# -ge 2 ] || die "Для --variant требуется значение" "$EXIT_USAGE"
                TARGET_VARIANT="$2"
                shift 2
                ;;
            help|version|check-os|list|install|doctor|interactive)
                COMMAND="$1"
                shift
                REMAINING_ARGS=("$@")
                return 0
                ;;
            *)
                die "Неизвестный аргумент: $1" "$EXIT_USAGE"
                ;;
        esac
    done
}

parse_install_args() {
    TARGET_COMPONENT="${REMAINING_ARGS[0]:-}"
}

# ------------------------------
# 13. Bootstrap / entrypoint
# ------------------------------

bootstrap() {
    init_colors
    detect_os_version
}

dispatch_command() {
    case "$COMMAND" in
        ""|help)
            cmd_help
            ;;
        version)
            cmd_version
            ;;
        check-os)
            cmd_check_os
            ;;
        list)
            cmd_list
            ;;
        install)
            parse_install_args
            cmd_install "$TARGET_COMPONENT"
            ;;
        doctor)
            cmd_doctor
            ;;
        interactive)
            cmd_interactive
            ;;
        *)
            die "Неизвестная команда: $COMMAND" "$EXIT_USAGE"
            ;;
    esac
}

main() {
    parse_global_args "$@"
    bootstrap
    dispatch_command
}

main "$@"
