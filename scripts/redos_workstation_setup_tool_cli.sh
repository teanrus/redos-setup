#!/bin/bash
##############################################################################
# redos_workstation_setup_tool_cli.sh — CLI-интерфейс для настройки РЕД ОС
#
# Описание:
#   Командная строка для автоматизированной настройки РЕД ОС.
#   Предоставляет интерфейс командной строки для установки компонентов,
#   управления конфигурацией и выполнения задач настройки системы.
#
# Использование:
#   ./redos_workstation_setup_tool_cli.sh [опции] [команды]
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

# --- Timedate configuration ---
NTP_SERVERS="ntp1.vniiftri.ru ntp2.vniiftri.ru ntp21.vniiftri.ru"
declare -a TZ_NAMES=(
    "Калининград (UTC+2)"
    "Москва (UTC+3)"
    "Самара (UTC+4)"
    "Екатеринбург (UTC+5)"
    "Омск (UTC+6)"
    "Красноярск (UTC+7)"
    "Иркутск (UTC+8)"
    "Якутск (UTC+9)"
    "Владивосток (UTC+10)"
    "Магадан (UTC+11)"
    "Камчатка (UTC+12)"
)

declare -a TZ_VALUES=(
    "Europe/Kaliningrad"
    "Europe/Moscow"
    "Europe/Samara"
    "Asia/Yekaterinburg"
    "Asia/Omsk"
    "Asia/Krasnoyarsk"
    "Asia/Irkutsk"
    "Asia/Yakutsk"
    "Asia/Vladivostok"
    "Asia/Magadan"
    "Asia/Kamchatka"
)

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
# Reserved for future non-interactive SELinux policy controls.
# shellcheck disable=SC2034
MANAGE_SELINUX_POLICIES=0
INSTALLED_APPS=()

# shellcheck disable=SC2034
EXIT_OK=0
EXIT_ERROR=1
EXIT_USAGE=2
EXIT_ROOT_REQUIRED=3
# shellcheck disable=SC2034
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

confirm_removal() {
    local component_label="$1"

    if [ "$NON_INTERACTIVE" -eq 1 ] || [ "$DIRECT_INSTALL_MODE" -eq 1 ]; then
        return 0
    fi

    local answer
    answer=$(read_from_terminal "${YELLOW}Удалить $component_label? (y/n)${NC}")
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
        run_cmd dnf install -y "$cmd" || die "Ошибка установки $cmd" "$EXIT_MISSING_DEPENDENCY"
    fi
}

is_package_installed() {
    rpm -q "$1" >/dev/null 2>&1
}

is_any_package_installed() {
    local package_name
    for package_name in "$@"; do
        if is_package_installed "$package_name"; then
            return 0
        fi
    done
    return 1
}

is_repo_configured() {
    local repo_name="$1"
    [ -f "/etc/yum.repos.d/$repo_name.repo" ] || grep -q "^\[$repo_name\]" /etc/yum.repos.d/*.repo 2>/dev/null
}

remove_installed_packages() {
    local label="$1"
    shift
    local -a installed_packages=()
    local package_name

    for package_name in "$@"; do
        if is_package_installed "$package_name"; then
            installed_packages+=("$package_name")
        fi
    done

    if [ "${#installed_packages[@]}" -eq 0 ]; then
        log_success "✓ $label не установлен"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] dnf remove -y ${installed_packages[*]}"
        return 0
    fi

    run_cmd dnf remove -y "${installed_packages[@]}" || die "Ошибка удаления $label"
    log_success "✓ $label удалён"
}

remove_path_if_exists() {
    local path="$1"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] rm -rf $path"
        return 0
    fi

    rm -rf "$path" || die "Ошибка удаления $path"
}

remove_exact_line_from_file() {
    local file="$1"
    local line="$2"
    local temp_file
    local file_mode

    if [ ! -f "$file" ] || ! grep -Fxq "$line" "$file"; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] remove line from $file: $line"
        return 0
    fi

    temp_file=$(mktemp) || die "Не удалось создать временный файл"
    file_mode=$(stat -c '%a' "$file" 2>/dev/null || echo 755)
    grep -Fxv "$line" "$file" > "$temp_file" || true
    mv "$temp_file" "$file" || die "Не удалось обновить $file"
    chmod "$file_mode" "$file" 2>/dev/null || chmod 755 "$file"
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
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/latest/$file_name"
}

get_assets_release_url() {
    local file_name="$1"
    get_release_asset_url "$ASSETS_RELEASE_TAG" "$file_name"
}

get_installed_kernel_packages() {
    local image_path
    local package_name
    local -a kernel_packages=()

    shopt -s nullglob
    for image_path in /boot/vmlinuz-*; do
        if [[ "$image_path" == *"/vmlinuz-0-rescue-"* ]]; then
            continue
        fi

        package_name=$(rpm -qf "$image_path" --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null || true)
        if [ -n "$package_name" ]; then
            kernel_packages+=("$package_name")
        fi
    done
    shopt -u nullglob

    if [ ${#kernel_packages[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${kernel_packages[@]}" | sort -u
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

prepare_remove_runtime() {
    if [ "$DRY_RUN" -ne 1 ]; then
        require_root
    fi
    require_tty_if_needed
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
        kernel)
            [ "$IS_REDOS" -eq 1 ] && [ "$OS_MAJOR_VERSION" = "7" ]
            ;;
        *)
            return 0
            ;;
    esac
}

component_support_reason() {
    local component_name="$1"

    case "$component_name" in
        cryptopro|vipnet|kernel)
            if [ "$IS_REDOS" -ne 1 ]; then
                echo "компонент поддерживается только на РЕД ОС, а текущая ОС не распознана как РЕД ОС"
            elif [ -z "$OS_MAJOR_VERSION" ]; then
                echo "не удалось определить основную версию РЕД ОС"
            elif [ "$component_name" = "kernel" ]; then
                echo "отдельное обновление ядра через redos-kernels6 доступно только на РЕД ОС 7.x; на РЕД ОС 8+ ядро обновляется через обычный dnf update"
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
    url=$(get_latest_release_url "redos_workstation_setup_tool_cli.sh")

    if curl -s --head -f "$url" >/dev/null 2>&1; then
        log_success "release asset redos_workstation_setup_tool_cli.sh: ok"
    else
        log_warn "release asset redos_workstation_setup_tool_cli.sh: не найден"
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

    local selinux_current
    selinux_current=$(grep '^SELINUX=' /etc/selinux/config 2>/dev/null | cut -d= -f2)
    
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
            if semodule -i redos_setup.pp 2>/dev/null; then
                log_success "✓ Политики SELinux применены"
            fi
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
    local file_mode

    if [ ! -f "$file" ]; then
        die "Файл $file не найден"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] insert line before exit 0 in $file: $line"
        return 0
    fi

    if grep -Fxq "$line" "$file"; then
        log_success "✓ Настройка уже применена: $line"
        return 0
    fi

    temp_file=$(mktemp) || die "Не удалось создать временный файл"
    file_mode=$(stat -c '%a' "$file" 2>/dev/null || echo 755)

    while IFS= read -r file_line; do
        if [[ "$file_line" =~ ^[[:space:]]*exit[[:space:]]+0 ]]; then
            echo "$line" >> "$temp_file"
        fi
        echo "$file_line" >> "$temp_file"
    done < "$file"

    mv "$temp_file" "$file" || die "Не удалось обновить $file"
    chmod "$file_mode" "$file" 2>/dev/null || chmod 755 "$file"
}

write_max_repo() {
    if is_repo_configured "max"; then
        log_success "✓ Репозиторий MAX уже настроен"
        return 0
    fi

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
# 7. Installers: workstation parity
# ------------------------------

install_updates() {
    confirm_installation "$(component_label update-system)" || return 0

    log_info "=== Обновление системы ==="
    run_cmd dnf clean all || die "Ошибка очистки кэша DNF"
    run_cmd dnf makecache || die "Ошибка обновления кэша DNF"
    run_cmd dnf update -y || die "Ошибка обновления системы"
    log_success "✓ Обновление системы выполнено"
}

install_kernel() {
    if ! is_component_supported "kernel"; then
        return 0
    fi

    confirm_installation "$(component_label kernel)" || return 0

    log_info "=== Обновление ядра ==="
    if ! rpm -q redos-kernels6-release >/dev/null 2>&1; then
        run_cmd dnf install -y redos-kernels6-release || die "Ошибка установки репозитория redos-kernels6"
    fi

    run_cmd dnf update -y || die "Ошибка обновления после подключения redos-kernels6"

    if confirm_installation "$(component_label grub) после установки ядра"; then
        local kernel_count
        local -a kernel_pkgs=()
        mapfile -t kernel_pkgs < <(get_installed_kernel_packages | sort -V || true)
        kernel_count=${#kernel_pkgs[@]}

        if [ "$kernel_count" -gt 3 ]; then
            local k
            local -a kernels_to_remove=( "${kernel_pkgs[@]:0:$((kernel_count - 3))}" )
            for k in "${kernels_to_remove[@]}"; do
                run_cmd dnf remove -y "$k" || die "Ошибка удаления старого ядра: $k"
            done
        fi

        update_grub
    fi

    log_success "✓ Обновление ядра выполнено"
}

install_yandex_browser() {
    confirm_installation "$(component_label yandex-browser)" || return 0

    if is_package_installed yandex-browser-stable; then
        log_success "✓ Яндекс.Браузер уже установлен"
        return 0
    fi

    if ! is_repo_configured "yandex-browser" && ! is_package_installed yandex-browser-release; then
        run_cmd dnf install -y yandex-browser-release || log_warn "Не удалось установить yandex-browser-release, продолжаю попытку установки браузера"
    fi

    run_cmd dnf install -y yandex-browser-stable || die "Ошибка установки Яндекс.Браузера"
    log_success "✓ Яндекс.Браузер установлен"
}

install_r7_office() {
    confirm_installation "$(component_label r7-office)" || return 0

    if is_package_installed r7-office; then
        log_success "✓ R7 Office уже установлен"
        return 0
    fi

    if ! is_repo_configured "r7-office" && ! is_package_installed r7-release; then
        run_cmd dnf install -y r7-release || die "Ошибка установки репозитория R7"
    fi

    run_cmd dnf install -y r7-office || die "Ошибка установки R7 Office"
    log_success "✓ R7 Office установлен"
}

install_max() {
    confirm_installation "$(component_label max)" || return 0

    if is_package_installed max; then
        log_success "✓ MAX уже установлен"
        return 0
    fi

    write_max_repo || die "Ошибка создания репозитория MAX"
    run_cmd rpm --import https://download.max.ru/linux/rpm/public.asc || die "Ошибка импорта ключа MAX"
    run_cmd dnf install -y max || die "Ошибка установки MAX"
    log_success "✓ MAX установлен"
}

timedate_select_timezone() {
    echo "" >&2
    log_info "[Выбор часового пояса]" >&2
    log_info "Можно ввести номер из списка или смещение UTC, например +5." >&2
    local i
    for i in "${!TZ_NAMES[@]}"; do
        echo "  $((i + 1)). ${TZ_NAMES[$i]}" >&2
    done
    echo "" >&2

    local choice
    while true; do
        choice=$(read_from_terminal "Выберите номер часового пояса [2]: ")
        choice=${choice:-2}
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TZ_NAMES[@]}" ]; then
            echo "$choice"
            return 0
        fi

        if [[ "$choice" =~ ^\+([0-9]+)$ ]]; then
            local offset="${BASH_REMATCH[1]}"
            if [ "$offset" -ge 2 ] && [ "$offset" -le 12 ]; then
                echo "$((offset - 1))"
                return 0
            fi
        fi

        log_warn "Неверный выбор. Введите номер от 1 до ${#TZ_NAMES[@]} или смещение UTC (+2…+12)" >&2
    done
}

timedate_wait_for_sync() {
    confirm_installation "ожидание синхронизации времени (до ~30 секунд)" || {
        log_warn "Пропуск ожидания синхронизации"
        return 0
    }

    local i
    local status
    echo "Ожидание синхронизации времени (до 30 секунд)..."
    for i in {1..6}; do
        sleep 5
        status=$(chronyc tracking 2>/dev/null | awk -F': ' '/Leap status/ {print $2}' | xargs || true)
        if [ -z "$status" ]; then
            status=$(chronyc tracking 2>/dev/null | awk -F': ' '/Статус прыжка/ {print $2}' | xargs || true)
        fi
        if [ "$status" = "Normal" ]; then
            log_success "✓ Синхронизация времени выполнена"
            return 0
        fi
        echo "  Попытка $i/6..."
    done

    log_warn "Синхронизация не завершена. Проверьте позже: chronyc tracking"
}

setup_timedate() {
    confirm_installation "$(component_label timedate)" || return 0

    local selected_tz
    selected_tz=$(timedate_select_timezone)
    local tz_index=$((selected_tz - 1))
    local timezone="${TZ_VALUES[$tz_index]}"

    run_cmd timedatectl set-timezone "$timezone" || die "Ошибка установки часового пояса"
    run_cmd timedatectl set-ntp false || die "Ошибка отключения текущего NTP"
    run_cmd dnf install -y chrony || die "Ошибка установки chrony"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] write /etc/chrony.conf"
    else
        cp /etc/chrony.conf "/etc/chrony.conf.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        cat > /etc/chrony.conf << EOF
# Серверы точного времени ВНИИФТРИ (Stratum-1, Россия)
$(echo "$NTP_SERVERS" | tr ' ' '\n' | sed 's/^/server /; s/$/ iburst maxsources 4/')

driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
log measurements statistics tracking
keyfile /etc/chrony.keys
EOF
    fi

    run_cmd systemctl enable chronyd || die "Ошибка включения chronyd"
    run_cmd systemctl restart chronyd || die "Ошибка перезапуска chronyd"
    [ "$DRY_RUN" -eq 1 ] || timedate_wait_for_sync
    log_success "✓ Настройка времени выполнена"
}

setup_auto_update() {
    confirm_installation "$(component_label auto-update)" || return 0

    local conf_file="/etc/redos-auto-update.conf"
    local wrapper_script="/usr/local/bin/redos-auto-update"
    local service_file="/etc/systemd/system/redos-auto-update.service"
    local timer_file="/etc/systemd/system/redos-auto-update.timer"
    local start_time end_time mode period

    start_time=$(read_from_terminal "Время начала окна обновлений [12:30]: ")
    start_time=${start_time:-12:30}
    end_time=$(read_from_terminal "Время окончания окна обновлений [14:00]: ")
    end_time=${end_time:-14:00}
    mode=$(read_from_terminal "Режим (security/full/check-only) [security]: ")
    mode=${mode:-security}
    period=$(read_from_terminal "Период (daily или OnCalendar spec) [daily]: ")
    period=${period:-daily}

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] write $conf_file"
        echo "[dry-run] write $wrapper_script"
        echo "[dry-run] write $service_file"
        echo "[dry-run] write $timer_file"
        echo "[dry-run] systemctl daemon-reload"
        echo "[dry-run] systemctl enable --now redos-auto-update.timer"
        return 0
    fi

    cat > "$conf_file" << EOF
# Конфиг redos-auto-update
START_TIME="$start_time"
END_TIME="$end_time"
MODE="$mode"
PERIOD="$period"
EOF
    chmod 600 "$conf_file"

    cat > "$wrapper_script" << 'EOF'
#!/bin/bash
CONF_FILE="/etc/redos-auto-update.conf"
LOG_FILE="/var/log/redos-auto-update.log"
source /etc/redos-auto-update.conf
now=$(date +"%H:%M")
time_to_minutes(){ h=${1%%:*}; m=${1##*:}; echo $((10#$h*60+10#$m)); }
if [ $(time_to_minutes "$now") -lt $(time_to_minutes "$START_TIME") ] || [ $(time_to_minutes "$now") -gt $(time_to_minutes "$END_TIME") ]; then
  echo "Outside window, exit" >> "$LOG_FILE"
  exit 0
fi
echo "Run update: $(date)" >> "$LOG_FILE"
dnf makecache -q
count=$(dnf check-update -q 2>/dev/null | grep -c "^[a-z]" || true)
echo "Updates: $count" >> "$LOG_FILE"
if [ "$count" -gt 0 ]; then
  if [ "$MODE" = "full" ]; then
    dnf upgrade -y >> "$LOG_FILE" 2>&1
  elif [ "$MODE" = "security" ]; then
    dnf upgrade --security -y >> "$LOG_FILE" 2>&1
  fi
fi
EOF
    chmod +x "$wrapper_script"

    cat > "$service_file" << EOF
[Unit]
Description=RED OS Automatic Update
After=network.target

[Service]
Type=oneshot
ExecStart=$wrapper_script

[Install]
WantedBy=multi-user.target
EOF

    cat > "$timer_file" << EOF
[Unit]
Description=RED OS Automatic Update Timer

[Timer]
OnCalendar=$period
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload || true
    systemctl enable --now redos-auto-update.timer || true
    log_success "✓ Автоматическое обновление настроено"
}

# ------------------------------
# 8. Installers: optional apps
# ------------------------------

install_liberation_fonts() {
    confirm_installation "$(component_label liberation-fonts)" || return 0

    if [ -d /usr/share/fonts/liberation ] && [ -n "$(ls -A /usr/share/fonts/liberation 2>/dev/null)" ]; then
        log_success "✓ Шрифты Liberation уже установлены"
        return 0
    fi

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

    if is_package_installed chromium-gost-stable; then
        log_success "✓ Chromium-GOST уже установлен"
        return 0
    fi

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

    if is_package_installed sreda; then
        log_success "✓ Среда уже установлена"
        return 0
    fi

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

    if is_package_installed vk-messenger; then
        log_success "✓ VK Messenger уже установлен"
        return 0
    fi

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

    if [ -x /opt/telegram/Telegram ] || command -v telegram >/dev/null 2>&1; then
        log_success "✓ Telegram уже установлен"
        return 0
    fi

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

    if [ -d /opt/kaspersky ] || is_any_package_installed klnagent kesl; then
        log_success "✓ Kaspersky Agent уже установлен"
        return 0
    fi

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

    if is_any_package_installed vipnetclient-gui_gost_ru_x86-64 vipnetclient-gui_gost_x86-64; then
        log_success "✓ ViPNet Client уже установлен"
        return 0
    fi

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

    if is_any_package_installed vipnetbusinessmail_ru_x86-64 vipnetclient-gui_gost_ru_x86-64 vipnetclient-gui_gost_x86-64; then
        log_success "✓ ViPNet или Деловая почта уже установлены"
        return 0
    fi

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

    if [ -d /opt/1cv8 ] || [ -d /opt/1C ] || [ -d /usr/lib1cv8 ]; then
        log_success "✓ 1С:Предприятие уже установлена"
        return 0
    fi

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
# 10. Removal helpers
# ------------------------------

remove_yandex_browser() {
    remove_installed_packages "$(component_label yandex-browser)" yandex-browser-stable yandex-browser-release
}

remove_r7_office() {
    remove_installed_packages "$(component_label r7-office)" r7-office r7-release
}

remove_max() {
    remove_installed_packages "$(component_label max)" max
    remove_path_if_exists /etc/yum.repos.d/max.repo
    log_success "✓ Репозиторий MAX удалён, если был создан скриптом"
}

remove_liberation_fonts() {
    remove_path_if_exists /usr/share/fonts/liberation
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] fc-cache -fv"
    elif command -v fc-cache >/dev/null 2>&1; then
        fc-cache -fv >/dev/null 2>&1 || true
    fi
    log_success "✓ Шрифты Liberation удалены"
}

remove_chromium_gost() {
    remove_installed_packages "$(component_label chromium-gost)" chromium-gost-stable chromium-gost
}

remove_sreda() {
    remove_installed_packages "$(component_label sreda)" sreda
}

remove_vk_messenger() {
    remove_installed_packages "$(component_label vk-messenger)" vk-messenger
}

remove_telegram() {
    remove_path_if_exists /opt/telegram
    remove_path_if_exists /usr/bin/telegram
    remove_path_if_exists /usr/share/applications/telegram.desktop
    log_success "✓ Telegram удалён"
}

remove_messengers_group() {
    remove_sreda
    remove_vk_messenger
    remove_telegram
}

remove_kaspersky() {
    remove_installed_packages "$(component_label kaspersky)" klnagent kesl
    remove_path_if_exists /opt/kaspersky
}

remove_vipnet() {
    remove_installed_packages "$(component_label vipnet)" \
        vipnetclient-gui_gost_ru_x86-64 \
        vipnetclient-gui_gost_x86-64 \
        vipnetbusinessmail_ru_x86-64
}

remove_1c() {
    remove_installed_packages "$(component_label 1c)" 1c-enterprise 1c-enterprise83-common 1c-enterprise83-server 1c-enterprise83-client
    remove_path_if_exists /opt/1cv8
    remove_path_if_exists /opt/1C
    remove_path_if_exists /usr/lib1cv8
}

remove_trim() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] systemctl disable --now fstrim.timer"
    else
        systemctl disable --now fstrim.timer || true
    fi
    log_success "✓ TRIM timer отключён"
}

remove_ksg() {
    remove_exact_line_from_file "/etc/gdm/Init/Default" "xrandr --output HDMI-3 --primary"
    log_success "✓ Настройка KSG удалена"
}

remove_timedate() {
    remove_installed_packages "$(component_label timedate)" chrony
}

remove_auto_update() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] systemctl disable --now redos-auto-update.timer"
        echo "[dry-run] rm -f /etc/redos-auto-update.conf /usr/local/bin/redos-auto-update /etc/systemd/system/redos-auto-update.service /etc/systemd/system/redos-auto-update.timer"
        return 0
    fi

    systemctl disable --now redos-auto-update.timer 2>/dev/null || true
    rm -f /etc/redos-auto-update.conf \
        /usr/local/bin/redos-auto-update \
        /etc/systemd/system/redos-auto-update.service \
        /etc/systemd/system/redos-auto-update.timer
    systemctl daemon-reload 2>/dev/null || true
    log_success "✓ Автоматическое обновление удалено"
}

# ------------------------------
# 11a. Workstation-compatible overrides
# ------------------------------

install_base_system() {
    confirm_installation "$(component_label base)" || return 0
    log_info "=== Базовая подготовка системы ==="
    install_updates
    install_kernel
    log_success "✓ Базовая подготовка системы выполнена"
}

component_exists() {
    local component="$1"
    case "$component" in
        base|update-system|kernel|yandex-browser|r7-office|max|liberation-fonts|chromium-gost|sreda|vk-messenger|telegram|messengers|kaspersky|vipnet|1c|trim|grub|ksg|timedate|auto-update|all)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

component_removable() {
    local component="$1"
    case "$component" in
        yandex-browser|r7-office|max|liberation-fonts|chromium-gost|sreda|vk-messenger|telegram|messengers|kaspersky|vipnet|1c|trim|ksg|timedate|auto-update|all)
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
        update-system) echo "обновление системы" ;;
        kernel) echo "обновление ядра для РЕД ОС 7.x" ;;
        yandex-browser) echo "Яндекс.Браузер" ;;
        r7-office) echo "R7 Office" ;;
        max) echo "MAX" ;;
        liberation-fonts) echo "шрифты Liberation" ;;
        chromium-gost) echo "Chromium-GOST" ;;
        sreda) echo "Среда" ;;
        vk-messenger) echo "VK Messenger" ;;
        telegram) echo "Telegram" ;;
        messengers) echo "группу мессенджеров" ;;
        kaspersky) echo "Kaspersky Agent" ;;
        vipnet) echo "ViPNet" ;;
        1c) echo "1С:Предприятие" ;;
        trim) echo "TRIM для SSD" ;;
        grub) echo "обновление GRUB" ;;
        ksg) echo "настройку для моноблока KSG" ;;
        timedate) echo "настройку времени и chrony" ;;
        auto-update) echo "настройку автоматического обновления" ;;
        all) echo "все совместимые компоненты" ;;
        *) echo "$component" ;;
    esac
}

component_group() {
    local component="$1"
    case "$component" in
        base) echo "base" ;;
        update-system|kernel|trim|grub|ksg|timedate|auto-update) echo "system" ;;
        yandex-browser|r7-office|max|liberation-fonts|chromium-gost|sreda|vk-messenger|telegram|messengers|kaspersky|vipnet|1c) echo "apps" ;;
        all) echo "meta" ;;
        *) echo "unknown" ;;
    esac
}

list_all_components() {
    cat << 'EOF'
base
update-system
kernel
yandex-browser
r7-office
max
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
messengers
kaspersky
vipnet
1c
trim
grub
ksg
timedate
auto-update
all
EOF
}

run_component_install() {
    local component="$1"

    case "$component" in
        base) install_base_system ;;
        update-system) install_updates ;;
        kernel) install_kernel ;;
        yandex-browser) install_yandex_browser ;;
        r7-office) install_r7_office ;;
        max) install_max ;;
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
        timedate) setup_timedate ;;
        auto-update) setup_auto_update ;;
        all) install_all_compatible ;;
        *) die "Неизвестный компонент: $component" "$EXIT_USAGE" ;;
    esac
}

run_component_remove() {
    local component="$1"

    case "$component" in
        yandex-browser) remove_yandex_browser ;;
        r7-office) remove_r7_office ;;
        max) remove_max ;;
        liberation-fonts) remove_liberation_fonts ;;
        chromium-gost) remove_chromium_gost ;;
        sreda) remove_sreda ;;
        vk-messenger) remove_vk_messenger ;;
        telegram) remove_telegram ;;
        messengers) remove_messengers_group ;;
        kaspersky) remove_kaspersky ;;
        vipnet) remove_vipnet ;;
        1c) remove_1c ;;
        trim) remove_trim ;;
        ksg) remove_ksg ;;
        timedate) remove_timedate ;;
        auto-update) remove_auto_update ;;
        all) remove_all_removable ;;
        base|update-system|kernel|grub)
            log_warn "$(component_label "$component") не удаляется автоматически"
            ;;
        *) die "Неизвестный компонент: $component" "$EXIT_USAGE" ;;
    esac
}

install_all_compatible() {
    local component
    while IFS= read -r component; do
        [ "$component" = "all" ] && continue
        if [ "$component" = "update-system" ] || [ "$component" = "kernel" ]; then
            continue
        fi
        if is_component_supported "$component"; then
            run_component_install "$component"
        else
            warn_component_not_supported "$component"
        fi
    done << 'EOF'
base
update-system
kernel
yandex-browser
r7-office
max
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
kaspersky
vipnet
1c
trim
grub
ksg
timedate
auto-update
EOF
}

remove_all_removable() {
    local component
    while IFS= read -r component; do
        [ "$component" = "all" ] && continue
        if component_removable "$component"; then
            run_component_remove "$component"
        fi
    done << 'EOF'
yandex-browser
r7-office
max
liberation-fonts
chromium-gost
sreda
vk-messenger
telegram
kaspersky
vipnet
1c
trim
ksg
timedate
auto-update
EOF
}

component_requires_variant() {
    local component="$1"
    [ "$component" = "vipnet" ]
}

cmd_help() {
    cat << 'EOF'
redos-setup - CLI для настройки рабочих мест на РЕД ОС

Usage:
  redos_workstation_setup_tool_cli.sh help
  redos_workstation_setup_tool_cli.sh version
  redos_workstation_setup_tool_cli.sh check-os
  redos_workstation_setup_tool_cli.sh list [--compatible]
  redos_workstation_setup_tool_cli.sh install <component> [options]
  redos_workstation_setup_tool_cli.sh remove <component> [options]
  redos_workstation_setup_tool_cli.sh doctor
  redos_workstation_setup_tool_cli.sh interactive

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
  remove <component>
      Удалить установленную программу или настройку, если поддерживается
  doctor
      Выполнить базовую диагностику среды
  interactive
      Запустить workstation-сценарий в стиле redos_workstation_setup_tool.sh

Components:
  base
  update-system
  kernel
  yandex-browser
  r7-office
  max
  liberation-fonts
  chromium-gost
  sreda
  vk-messenger
  telegram
  messengers
  kaspersky
  vipnet
  1c
  trim
  grub
  ksg
  timedate
  auto-update
  all

Removable components:
  yandex-browser
  r7-office
  max
  liberation-fonts
  chromium-gost
  sreda
  vk-messenger
  telegram
  messengers
  kaspersky
  vipnet
  1c
  trim
  ksg
  timedate
  auto-update
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
    apply_policies_for_all_apps
}

cmd_remove() {
    local component="$1"

    [ -n "$component" ] || die "Не указан компонент для remove" "$EXIT_USAGE"
    component_exists "$component" || die "Неизвестный компонент: $component" "$EXIT_USAGE"

    if ! component_removable "$component"; then
        die "Компонент не поддерживает автоматическое удаление: $component" "$EXIT_USAGE"
    fi

    DIRECT_INSTALL_MODE=1
    prepare_remove_runtime
    confirm_removal "$(component_label "$component")" || return 0
    run_component_remove "$component"
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
    done < <(list_all_components)
}

cmd_interactive() {
    detect_os_version
    check_selinux_status
    prepare_runtime
    prepare_system_defaults

    log_info "=== Начало настройки РЕД ОС ==="
    log_info "Дата запуска: $(date)"
    show_os_compatibility_info
    echo ""

    install_updates
    install_kernel
    install_yandex_browser
    install_r7_office
    install_max
    install_sreda
    install_chromium_gost
    install_liberation_fonts
    install_kaspersky
    if is_component_supported "vipnet"; then
        DIRECT_INSTALL_MODE=0
        install_vipnet
    else
        warn_component_not_supported "vipnet"
    fi
    install_1c
    setup_trim
    setup_ksg
    setup_timedate
    setup_auto_update
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
                # shellcheck disable=SC2034
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
            help|version|check-os|list|install|remove|uninstall|doctor|interactive)
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
    TARGET_COMPONENT="${1:-}"
    local arg
    shift || true

    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --variant)
                [ $# -ge 2 ] || die "Для --variant требуется значение" "$EXIT_USAGE"
                TARGET_VARIANT="$2"
                shift 2
                ;;
            --workdir)
                [ $# -ge 2 ] || die "Для --workdir требуется путь" "$EXIT_USAGE"
                WORK_DIR="$2"
                shift 2
                ;;
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
                # shellcheck disable=SC2034
                FORCE=1
                shift
                ;;
            *)
                die "Неизвестный аргумент install: $arg" "$EXIT_USAGE"
                ;;
        esac
    done
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
            parse_install_args "${REMAINING_ARGS[@]}"
            cmd_install "$TARGET_COMPONENT"
            ;;
        remove|uninstall)
            parse_install_args "${REMAINING_ARGS[@]}"
            cmd_remove "$TARGET_COMPONENT"
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
