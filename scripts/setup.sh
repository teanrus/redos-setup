#!/bin/bash
# Автоматизированная настройка РЕД ОС 7.3
# GitHub: https://github.com/teanrus/redos-setup
# Версия: 2.8

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === КОНФИГУРАЦИЯ GITHUB ===
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
# Используем latest релиз вместо фиксированной версии

# === ФУНКЦИИ ===

# Функция для получения URL последнего релиза
get_latest_release_url() {
    local file_name=$1
    echo "https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$file_name"
}

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
    
    local url=$(get_latest_release_url "$file_name")
    
    echo -e "${BLUE}Загрузка $file_name...${NC}"
    
    if ! curl -s --head -f "$url" > /dev/null 2>&1; then
        echo -e "${RED}✗ Файл $file_name не найден в последнем релизе${NC}"
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
select_vipnet_version() {
    echo -e "${GREEN}=== Выбор версии ViPNet ===${NC}" >&2
    echo "1. ViPNet Client (без деловой почты)" >&2
    echo "2. ViPNet + Деловая почта (DP)" >&2
    local choice=$(read_from_terminal "${YELLOW}Выберите вариант (1 или 2):${NC}")
    
    case $choice in
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
    if confirm_installation "КриптоПро и дополнительные пакеты"; then
        echo -e "${GREEN}Установка КриптоПро...${NC}"
        
        dnf install -y ifd-rutokens token-manager gostcryptogui caja-gostcryptogui
        check_success "Установка пакетов для КриптоПро"
        
        download_from_github "kriptopror4.tar.gz" "$WORK_DIR"
        if [ -f "$WORK_DIR/kriptopror4.tar.gz" ]; then
            cd "$WORK_DIR"
            tar -xzf kriptopror4.tar.gz
            
            # Ищем установочный скрипт в текущей директории (без подкаталога R4)
            if [ -f "install_gui.sh" ]; then
                chmod +x install_gui.sh
                ./install_gui.sh
                check_success "Установка КриптоПро"
            elif [ -f "install.sh" ]; then
                chmod +x install.sh
                ./install.sh
                check_success "Установка КриптоПро"
            else
                # Если скрипт не найден, пробуем установить все rpm пакеты
                echo -e "${BLUE}Установка RPM пакетов КриптоПро...${NC}"
                for rpm in *.rpm; do
                    if [ -f "$rpm" ]; then
                        dnf install -y "$rpm"
                    fi
                done
                check_success "Установка КриптоПро (RPM)"
            fi
            
            cd "$WORK_DIR"
            rm -f kriptopror4.tar.gz
            # Удаляем распакованные файлы
            rm -f *.rpm *.sh 2>/dev/null
            rm -rf linux-amd64_deb 2>/dev/null
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

echo -e "${GREEN}=== Начало настройки РЕД ОС 7.3 ===${NC}"
echo -e "${BLUE}Дата запуска: $(date)${NC}"
echo -e "${BLUE}GitHub: https://github.com/$GITHUB_USER/$GITHUB_REPO${NC}"
echo ""

# Отключаем SELinux
if [ -f /etc/selinux/config ]; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    check_success "Отключение SELinux"
fi

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
if confirm_installation "ViPNet"; then
    select_vipnet_version
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