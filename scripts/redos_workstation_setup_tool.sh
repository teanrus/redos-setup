#!/bin/bash

##############################################################################
# redos_workstation_setup_tool.sh — Автоматизированная настройка РЕД ОС
#
# Описание:
#   Интерактивный скрипт для установки компонентов на РЕД ОС 7.x и 8+.
#   Выполняет выборочную установку системных и прикладных компонентов,
#   определяет версию ОС и загружает артефакты по мере необходимости.
#
# Использование:
#   sudo ./redos_workstation_setup_tool.sh
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
WORK_DIR="/home/inst"
 
# --- Параметры для настройки времени ---
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

# === ФУНКЦИИ ===

# Функция для безопасного чтения ввода из терминала
read_from_terminal() {
    local prompt="$1"
    local answer
    echo -e "$prompt" >&2
    read -r answer < /dev/tty 2>/dev/null || true
    echo "$answer"
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

# Функция для запроса подтверждения
confirm_installation() {
    local component_name="$1"
    local answer
    answer=$(read_from_terminal "${YELLOW}Выполнить $component_name? (y/n)${NC}")
    [[ $answer =~ ^[Yy]$ ]]
}

# ======================== Timedate ========================
timedate_select_timezone() {
    echo -e "${BLUE}[Выбор часового пояса]${NC}"
    echo "Можно ввести номер из списка или смещение UTC, например +5."
    echo ""
    for i in "${!TZ_NAMES[@]}"; do
        echo "  $((i+1)). ${TZ_NAMES[$i]}"
    done
    echo ""
    local choice
    while true; do
        choice=$(read_from_terminal "Выберите номер часового пояса [2]: ")
        choice=${choice:-2}

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TZ_NAMES[@]}" ]; then
            SELECTED_TZ=$choice
            break
        fi

        if [[ "$choice" =~ ^\+([0-9]+)$ ]]; then
            local offset="${BASH_REMATCH[1]}"
            if [ "$offset" -ge 2 ] && [ "$offset" -le 12 ]; then
                SELECTED_TZ=$((offset - 1))
                break
            fi
        fi

        echo -e "${RED}Неверный выбор. Введите номер от 1 до ${#TZ_NAMES[@]} или смещение UTC (+2…+12)${NC}"
    done
    echo ""
}

timedate_set_timezone() {
    local tz_index=$((SELECTED_TZ-1))
    local timezone="${TZ_VALUES[$tz_index]}"
    local tz_name="${TZ_NAMES[$tz_index]}"
    echo -e "${BLUE}Установка часового пояса: ${tz_name}${NC}"
    timedatectl set-timezone "$timezone"
    check_success "Часовой пояс"
    echo ""
}

timedate_disable_ntp() {
    echo -e "${BLUE}Отключение текущей синхронизации NTP...${NC}"
    timedatectl set-ntp false
    sleep 1
    check_success "Отключение NTP"
    echo ""
}

timedate_install_chrony() {
    echo -e "${BLUE}Установка chrony...${NC}"
    dnf install -y chrony > /dev/null 2>&1
    check_success "Установка chrony"
    cp /etc/chrony.conf "/etc/chrony.conf.backup.$(date +%Y%m%d_%H%M%S)" || true
    echo -e "${BLUE}Настройка серверов времени...${NC}"
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
    echo -e "${GREEN}Серверы времени настроены${NC}"
    echo ""
}

timedate_start_chronyd() {
    echo -e "${BLUE}Запуск службы chronyd...${NC}"
    systemctl enable chronyd
    systemctl restart chronyd
    check_success "Запуск chronyd"
    echo ""
}

timedate_wait_for_sync() {
    if ! confirm_installation "ожидание синхронизации времени (до ~30 секунд)"; then
        echo -e "${YELLOW}Пропуск ожидания синхронизации${NC}"
        return
    fi
    echo "Ожидание синхронизации времени (до 30 секунд)..."
    for i in {1..6}; do
        sleep 5
        STATUS=$(chronyc tracking 2>/dev/null | awk -F': ' '/Leap status/ {print $2}' | xargs || true)
        if [ -z "$STATUS" ]; then
            STATUS=$(chronyc tracking 2>/dev/null | awk -F': ' '/Статус прыжка/ {print $2}' | xargs || true)
        fi
        if [ "$STATUS" = "Normal" ]; then
            echo -e "${GREEN}Синхронизация выполнена!${NC}"
            return
        fi
        echo "  Попытка $i/6..."
    done
    echo -e "${YELLOW}Синхронизация не завершена. Проверьте позже: chronyc tracking${NC}"
}

setup_timedate() {
    if ! confirm_installation "настройку времени (timedate)"; then
        echo -e "${YELLOW}Пропускаем настройку времени${NC}"
        return
    fi
    timedate_select_timezone
    timedate_set_timezone
    timedate_disable_ntp
    timedate_install_chrony
    timedate_start_chronyd
    timedate_wait_for_sync
    echo ""
    echo -e "${BLUE}Итоговая информация:${NC}"
    date
    timedatectl status
    chronyc tracking 2>/dev/null || true
}

# ======================== Auto-update ========================
setup_auto_update() {
    if ! confirm_installation "настройку автоматического обновления (redos-auto-update)"; then
        echo -e "${YELLOW}Пропускаем настройку автоматического обновления${NC}"
        return
    fi

    local CONF_FILE="/etc/redos-auto-update.conf"
    local WRAPPER_SCRIPT="/usr/local/bin/redos-auto-update"
    local SERVICE_FILE="/etc/systemd/system/redos-auto-update.service"
    local TIMER_FILE="/etc/systemd/system/redos-auto-update.timer"

    # Простая конфигурация
    local start_time end_time mode period
    start_time=$(read_from_terminal "Время начала окна обновлений [12:30]: ")
    start_time=${start_time:-12:30}
    end_time=$(read_from_terminal "Время окончания окна обновлений [14:00]: ")
    end_time=${end_time:-14:00}
    mode=$(read_from_terminal "Режим (security/full/check-only) [security]: ")
    mode=${mode:-security}
    period=$(read_from_terminal "Период (daily или OnCalendar spec) [daily]: ")
    period=${period:-daily}

    cat > "$CONF_FILE" << EOF
# Конфиг redos-auto-update
START_TIME="$start_time"
END_TIME="$end_time"
MODE="$mode"
PERIOD="$period"
EOF
    chmod 600 "$CONF_FILE"

    # Обёртка (упрощённая) — вызывает dnf внутри окна
    cat > "$WRAPPER_SCRIPT" << 'WR'
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
  if [ "$MODE" = "full" ]; then dnf upgrade -y >> "$LOG_FILE" 2>&1; else dnf upgrade --security -y >> "$LOG_FILE" 2>&1; fi
fi
WR
    chmod +x "$WRAPPER_SCRIPT"

    # systemd unit
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=RED OS Automatic Update
After=network.target

[Service]
Type=oneshot
ExecStart=$WRAPPER_SCRIPT

[Install]
WantedBy=multi-user.target
EOF

    cat > "$TIMER_FILE" << EOF
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
    echo -e "${GREEN}Автоматическое обновление настроено и таймер включён (если systemd доступен)${NC}"
}

# Функция для проверки версии ОС
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

# Проверка наличия устанавливаемого софта
is_package_installed() {
    rpm -q "$1" &>/dev/null
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

# Проверка наличия репозитория
is_repo_configured() {
    local repo_name="$1"
    [ -f "/etc/yum.repos.d/$repo_name.repo" ] || grep -q "^\[$repo_name\]" /etc/yum.repos.d/*.repo 2>/dev/null
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

# === БЛОКИ УСТАНОВКИ ===

# Общее обновление
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

# Обновление ядра (только версия 7.х)
install_kernel() {
    if ! is_redos7; then
        return 0
    fi

    if confirm_installation "обновление ядра (redos-kernels6) для РЕД ОС 7.x"; then
        echo -e "${BLUE}Обновление ядра...${NC}"
        if ! is_package_installed redos-kernels6-release; then
            dnf install -y redos-kernels6-release
            check_success "установка репозитория ядра"
        fi
        dnf update -y
        check_success "Обновление после установки ядра"

        if confirm_installation "обновление конфигурации GRUB после установки ядра"; then
            # --- Безопасное удаление старых ядер ---
            echo -e "${BLUE}Проверка количества установленных ядер...${NC}"
            mapfile -t kernel_pkgs < <(get_installed_kernel_packages | sort -V || true)
            kernel_count=${#kernel_pkgs[@]}
            if [ "$kernel_count" -eq 0 ]; then
                echo -e "${YELLOW}Не удалось определить список пакетов ядер. Очистка старых ядер будет пропущена.${NC}"
            elif [ "$kernel_count" -le 3 ]; then
                echo -e "${GREEN}Ядер установлено $kernel_count. Удаление не требуется.${NC}"
            else
                echo -e "${YELLOW}Обнаружено $kernel_count ядер. Будут удалены старые, останутся только последние 3.${NC}"
                # Получаем список для удаления
                kernels_to_remove=( "${kernel_pkgs[@]:0:$((kernel_count-3))}" )
                for k in "${kernels_to_remove[@]}"; do
                    echo -e "${YELLOW}Удаление: $k${NC}"
                    dnf remove -y "$k"
                done
                echo -e "${GREEN}Старые ядра удалены. Остались:${NC}"
                get_installed_kernel_packages | sort -V || true
            fi
            # --- Пересоздание конфигурации GRUB ---
            grub2-mkconfig -o /boot/grub2/grub.cfg
            check_success "Обновление GRUB"
        fi
    else
        echo -e "${YELLOW}Пропускаем обновление ядра${NC}"
    fi
}

# установка Яндекс.Браузер
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
    else
        echo -e "${YELLOW}Пропускаем установку Яндекс.Браузера${NC}"
    fi
}

install_r7_office() {
    if confirm_installation "установку R7 Office"; then
        if ! is_package_installed r7-office; then
            if ! is_repo_configured "r7-office"; then
                dnf install -y r7-release
                check_success "установка репозитория R7"
            fi
            dnf install -y r7-office
            check_success "установка R7 Office"
        else
            echo -e "${GREEN}✓ R7 Office уже установлен${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку R7 Office${NC}"
    fi
}

# установка мессенджера MAX
install_max() {
    if confirm_installation "установку быстрого и легкого приложения для общения и решения повседневных задач Макс"; then
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
                check_success "установка репозитория MAX"
            fi
            dnf install -y max
            check_success "установка MAX"
        else
            echo -e "${GREEN}✓ MAX уже установлен${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку MAX${NC}"
    fi
}

install_sreda() {
    if confirm_installation "установку корпоративного мессенджера Среда"; then
        if ! is_package_installed sreda; then
            if download_from_github "sreda.rpm"; then
                dnf install -y "$WORK_DIR/sreda.rpm"
                check_success "установка Среда"
                rm -f "$WORK_DIR/sreda.rpm"
            fi
        else
            echo -e "${GREEN}✓ Среда уже установлена${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку Среда${NC}"
    fi
}

install_chromium_gost() {
    if confirm_installation "установку браузера Chromium-GOST (с поддержкой ГОСТ)"; then
        if ! is_package_installed chromium-gost-stable; then
            if download_from_github "chromium-gost-139.0.7258.139-linux-amd64.rpm"; then
                dnf install -y "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
                check_success "установка Chromium-GOST"
                rm -f "$WORK_DIR/chromium-gost-139.0.7258.139-linux-amd64.rpm"
            fi
        else
            echo -e "${GREEN}✓ Chromium-GOST уже установлен${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку Chromium-GOST${NC}"
    fi
}

install_liberation_fonts() {
    if confirm_installation "установку шрифтов Liberation"; then
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
                check_success "установка шрифтов Liberation"
            fi
        else
            echo -e "${GREEN}✓ Шрифты Liberation уже установлены${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку шрифтов Liberation${NC}"
    fi
}

install_kaspersky() {
    if confirm_installation "установку Kaspersky Agent"; then
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
                check_success "установка Kaspersky Agent"
                rm -f kasp.tar.gz ./*.sh
                cd - > /dev/null
            fi
        else
            echo -e "${GREEN}✓ Kaspersky Agent уже установлен${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку Kaspersky Agent${NC}"
    fi
}

install_vipnet() {
    if confirm_installation "установку ViPNet"; then
        if is_any_package_installed vipnetclient-gui_gost_ru_x86-64 vipnetclient-gui_gost_x86-64 vipnetbusinessmail_ru_x86-64; then
            echo -e "${GREEN}✓ ViPNet уже установлен${NC}"
            return
        fi

        echo -e "${GREEN}=== Выбор версии ViPNet ===${NC}"
        echo "1. ViPNet Client (без деловой почты)"
        echo "2. ViPNet + Деловая почта (DP)"
        local choice
        choice=$(read_from_terminal "${YELLOW}Выберите вариант (1 или 2):${NC}")
        
        if [ "$choice" = "1" ]; then
            local client_asset
            if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
                client_asset="vipnetclient-gui_gost_x86-64_5.1.3-8402.rpm"
            else
                client_asset="vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
            fi
            if download_from_github "$client_asset"; then
                dnf install -y "$WORK_DIR/$client_asset"
                check_success "установка ViPNet Client"
                rm -f "$WORK_DIR/$client_asset"
            fi
        elif [ "$choice" = "2" ]; then
            if [ -n "$OS_MAJOR_VERSION" ] && [ "$OS_MAJOR_VERSION" -ge 8 ]; then
                local client_asset="vipnetclient-gui_gost_x86-64_5.1.3-8402.rpm"
                if download_from_github "$client_asset" && download_from_github "vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"; then
                    dnf install -y "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
                    check_success "установка ViPNet + Деловая почта"
                    rm -f "$WORK_DIR/$client_asset" "$WORK_DIR/vipnetbusinessmail_ru_x86-64_1.4.2-5248.rpm"
                fi
            elif download_from_github "VipNet-DP.tar.gz"; then
                local extract_dir
                extract_dir=$(mktemp -d "$WORK_DIR/vipnet-dp.XXXXXX")
                tar -xzf "$WORK_DIR/VipNet-DP.tar.gz" -C "$extract_dir"
                check_success "распаковка ViPNet-DP.tar.gz"

                local -a rpm_files=()
                mapfile -d '' -t rpm_files < <(find "$extract_dir" -type f -name '*.rpm' -print0 | sort -z)
                if [ "${#rpm_files[@]}" -eq 0 ]; then
                    echo -e "${RED}✗ В архиве VipNet-DP.tar.gz не найдены RPM-пакеты${NC}"
                    rm -rf "$extract_dir"
                    rm -f "$WORK_DIR/VipNet-DP.tar.gz"
                    exit 1
                fi

                local rpm
                for rpm in "${rpm_files[@]}"; do
                    dnf install -y "$rpm"
                    check_success "установка ViPNet RPM: $rpm"
                done

                rm -rf "$extract_dir"
                rm -f "$WORK_DIR/VipNet-DP.tar.gz"
            fi
        else
            echo -e "${RED}Неверный выбор${NC}"
        fi
    else
        echo -e "${YELLOW}Пропускаем установку ViPNet${NC}"
    fi
}

install_1c() {
    if confirm_installation "установку 1С:Предприятие"; then
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
    else
        echo -e "${YELLOW}Пропускаем установку 1С:Предприятие${NC}"
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

# Функция настройки моноблока KSG
setup_ksg() {
    if confirm_installation "настройку для моноблока KSG"; then
        if [ -f "/etc/gdm/Init/Default" ]; then
            if ! grep -q "xrandr --output HDMI-3 --primary" /etc/gdm/Init/Default; then
                sed -i '/^[[:space:]]*exit[[:space:]]*0/i xrandr --output HDMI-3 --primary' /etc/gdm/Init/Default
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

# === Общее обновление системы ===
echo -e "${GREEN}=== Общее обновление системы ===${NC}"
install_updates
install_kernel
# install_extra_packages

# === ПРОГРАММЫ ===
echo -e "${GREEN}=== Выбор устанавливаемых программ ===${NC}"
install_yandex_browser
install_r7_office
install_max
install_sreda
install_chromium_gost
install_liberation_fonts
install_kaspersky
install_vipnet
install_1c

# === СИСТЕМНЫЕ НАСТРОЙКИ ===
echo -e "${GREEN}=== Системные настройки ===${NC}"
setup_trim
setup_ksg

# Опционально: настройка времени и авт-обновлений
setup_timedate
setup_auto_update

# === ЗАВЕРШЕНИЕ ===
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo -e "${BLUE}Время завершения: $(date)${NC}"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  ВНИМАНИЕ! Для корректной работы рекомендуется перезагрузить систему.${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

if confirm_installation "перезагрузку системы сейчас"; then
    echo -e "${BLUE}Перезагрузка через 5 секунд...${NC}"
    sleep 5
    sync
    reboot
else
    echo -e "${GREEN}Перезагрузка отменена. Выполните: sudo reboot${NC}"
fi
