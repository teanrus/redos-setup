#!/bin/bash
# Автоматизированная настройка РЕД ОС 7.3
# GitHub: https://github.com/teanrus/redos-setup
# Версия: 1.3

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# === КОНФИГУРАЦИЯ GITHUB ===
GITHUB_USER="teanrus"
GITHUB_REPO="redos-setup"
GITHUB_TAG="v1.3"

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
    local use_release=${3:-true}
    
    local url
    if [ "$use_release" = true ]; then
        if [ "$GITHUB_TAG" = "latest" ]; then
            url="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/latest/download/$file_name"
        else
            url="https://github.com/$GITHUB_USER/$GITHUB_REPO/releases/download/$GITHUB_TAG/$file_name"
        fi
    else
        url="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/$file_name"
    fi
    
    echo -e "${BLUE}Загрузка $file_name из GitHub...${NC}"
    echo -e "${BLUE}URL: $url${NC}"
    
    if ! curl -s --head "$url" | grep -E "200|302|301" > /dev/null; then
        echo -e "${RED}✗ Файл $file_name не найден на GitHub${NC}"
        return 1
    fi
    
    if wget --progress=bar:force -O "$dest_dir/$file_name" "$url" 2>&1; then
        echo -e "${GREEN}✓ $file_name успешно загружен (размер: $(numfmt --to=iec $(stat -c %s "$dest_dir/$file_name" 2>/dev/null)))${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка загрузки $file_name${NC}"
        return 1
    fi
}

# Функция скачивания через SMB
download_from_smb() {
    local server=$1
    local share=$2
    local user=$3
    local file=$4
    local dest=$5
    
    echo -e "${BLUE}Скачивание $file из локальной сети...${NC}"
    
    smbclient "//$server/$share" -U "$user" -c "prompt OFF; get $file $dest" &
    local smb_pid=$!
    
    show_progress $smb_pid
    wait $smb_pid
    
    if [ $? -eq 0 ] && [ -f "$dest" ]; then
        echo -e "${GREEN}✓ $file успешно скачан${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка скачивания $file${NC}"
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

# Функция настройки DNS для ViPNet (только для департамента образования)
setup_vipnet_dns() {
    echo -e "${GREEN}=== Настройка DNS для ViPNet (департамент образования) ===${NC}"
    
    # Проверка наличия файла конфигурации
    if [ ! -f "/etc/vipnet.conf" ]; then
        echo -e "${RED}✗ Файл /etc/vipnet.conf не найден${NC}"
        echo -e "${YELLOW}ViPNet не установлен в системе. Настройка DNS невозможна.${NC}"
        return 1
    fi
    
    # Создание резервной копии
    echo -e "${BLUE}Создание резервной копии /etc/vipnet.conf...${NC}"
    cp /etc/vipnet.conf /etc/vipnet.conf.backup.$(date +%Y%m%d_%H%M%S)
    check_success "Создание резервной копии ViPNet конфигурации"
    
    # Замена DNS-серверов на корпоративные (департамент образования)
    echo -e "${BLUE}Замена DNS-серверов на корпоративные (департамент образования)...${NC}"
    echo -e "${YELLOW}Старые DNS: 77.88.8.88,77.88.8.2${NC}"
    echo -e "${YELLOW}Новые DNS: 10.13.60.2,10.14.100.222${NC}"
    
    sed -i 's/77.88.8.88,77.88.8.2/10.13.60.2,10.14.100.222/' /etc/vipnet.conf
    check_success "Замена DNS-серверов"
    
    # Включение параметра iptables=off
    echo -e "${BLUE}Включение параметра iptables=off...${NC}"
    
    if grep -q ";iptables=off" /etc/vipnet.conf; then
        sed -i 's/;iptables=off/iptables=off/' /etc/vipnet.conf
        echo -e "${GREEN}✓ Параметр iptables=off раскомментирован${NC}"
    elif grep -q "iptables=off" /etc/vipnet.conf; then
        echo -e "${GREEN}✓ Параметр iptables=off уже активен${NC}"
    else
        echo "iptables=off" >> /etc/vipnet.conf
        echo -e "${GREEN}✓ Параметр iptables=off добавлен в конфигурацию${NC}"
    fi
    check_success "Настройка параметра iptables"
    
    # Проверка конфигурации
    echo -e "${BLUE}Проверка изменений в конфигурации...${NC}"
    echo -e "${YELLOW}Текущие DNS в конфигурации:${NC}"
    grep -E "^(;|)nameserver|dns" /etc/vipnet.conf | head -3
    
    echo -e "${YELLOW}Состояние параметра iptables:${NC}"
    grep "iptables" /etc/vipnet.conf
    
    # Предложение перезапустить ViPNet
    echo -e "${GREEN}✓ Настройка DNS для ViPNet завершена${NC}"
    echo -e "${YELLOW}Для применения изменений рекомендуется перезапустить ViPNet:${NC}"
    echo -e "${BLUE}  systemctl restart vipnet${NC}"
    echo -e "${YELLOW}Или перезагрузить систему.${NC}"
    
    return 0
}

# Функция установки ViPNet
install_vipnet() {
    echo -e "${GREEN}=== Установка ViPNet ===${NC}"
    
    # Здесь будет логика установки ViPNet
    # Например, установка из локального репозитория или скачивание
    
    echo -e "${BLUE}Поиск установочных файлов ViPNet...${NC}"
    
    # Проверяем наличие установочного файла
    if [ -f "$WORK_DIR/vipnet_install.sh" ]; then
        echo -e "${BLUE}Найден установочный файл ViPNet, запускаю установку...${NC}"
        chmod +x "$WORK_DIR/vipnet_install.sh"
        ./"$WORK_DIR/vipnet_install.sh"
        check_success "Установка ViPNet"
    else
        echo -e "${YELLOW}Установочный файл ViPNet не найден в $WORK_DIR${NC}"
        echo -e "${YELLOW}Пропускаем установку ViPNet${NC}"
        return 1
    fi
    
    return 0
}

# Функция проверки обновлений
check_for_updates() {
    local current_version="1.3"
    local latest_version
    
    echo -e "${BLUE}Проверка обновлений...${NC}"
    
    latest_version=$(curl -s "https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO/releases/latest" 2>/dev/null | grep '"tag_name"' | head -n 1 | cut -d '"' -f 4 | sed 's/^v//')
    
    if [ -z "$latest_version" ]; then
        echo -e "${YELLOW}Не удалось проверить обновления${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Текущая версия: $current_version${NC}"
    echo -e "${BLUE}Доступная версия: $latest_version${NC}"
    
    if [ "$current_version" != "$latest_version" ]; then
        echo -e "${YELLOW}Доступна новая версия!${NC}"
        echo -e "${YELLOW}Хотите обновить скрипт? (y/n)${NC}"
        read -r update_script
        if [[ $update_script =~ ^[Yy]$ ]]; then
            download_from_github "setup.sh" "/tmp" false
            if [ $? -eq 0 ]; then
                cp /tmp/setup.sh "$0"
                chmod +x "$0"
                echo -e "${GREEN}✓ Скрипт обновлен. Запустите его снова${NC}"
                exit 0
            fi
        fi
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

# Проверка обновлений
check_for_updates

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
check_command "smbclient"
check_command "wget"
check_command "curl"
check_command "numfmt"

# Выбор источника загрузки
echo -e "${GREEN}=== Выбор источника загрузки ===${NC}"
echo "1. GitHub (из интернета) - рекомендуется"
echo "2. Локальная сеть (SMB)"
echo -e "${YELLOW}Выберите источник (1 или 2):${NC}"
read -r source_choice

# Скачивание основного пакета
case $source_choice in
    1)
        echo -e "${GREEN}Использую GitHub репозиторий${NC}"
        
        if ! download_from_github "pack.tar.gz" "$WORK_DIR"; then
            echo -e "${RED}Не удалось загрузить pack.tar.gz из GitHub${NC}"
            echo -e "${YELLOW}Попробовать загрузить из локальной сети? (y/n)${NC}"
            read -r try_smb
            if [[ $try_smb =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}Введи пароль админа для скачивания пакетов:${NC}"
                if ! download_from_smb "10.13.60.3" "soft" "MKUUO.LBT.RF/admin" "RedOS/pack.tar.gz" "$WORK_DIR/pack.tar.gz"; then
                    exit 1
                fi
            else
                exit 1
            fi
        fi
        ;;
    2)
        echo -e "${GREEN}Использую локальную сеть${NC}"
        echo -e "${YELLOW}Введи пароль админа для скачивания пакетов:${NC}"
        if ! download_from_smb "10.13.60.3" "soft" "MKUUO.LBT.RF/admin" "RedOS/pack.tar.gz" "$WORK_DIR/pack.tar.gz"; then
            exit 1
        fi
        ;;
    *)
        echo -e "${RED}Неверный выбор${NC}"
        exit 1
        ;;
esac

# Распаковка с прогрессом
if [ -f "pack.tar.gz" ]; then
    echo -e "${BLUE}Распаковка архива...${NC}"
    
    if command -v pv &> /dev/null; then
        pv pack.tar.gz | tar -xzf -
    else
        tar -xzf pack.tar.gz &
        local tar_pid=$!
        show_progress $tar_pid
        wait $tar_pid
    fi
    
    rm -f pack.tar.gz
    check_success "Распаковка архива"
fi

# Обновление системы
echo -e "${GREEN}Обновление системы...${NC}"
dnf clean all
dnf makecache
dnf update -y
check_success "Обновление системы"

# === БЛОК УСТАНОВКИ РЕПОЗИТОРИЕВ ===
echo -e "${GREEN}Установка репозиториев...${NC}"

dnf install -y r7-release
check_success "Установка репозитория r7"

dnf install -y yandex-browser-release
check_success "Установка репозитория Яндекс Браузера"

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

dnf makecache
check_success "Обновление кэша репозиториев"

# === УСТАНОВКА ЯДРА ===
echo -e "${BLUE}Установка ядра...${NC}"
dnf install -y redos-kernels6-release
check_success "Установка ядра redos-kernels6"

# Финальное обновление
dnf update -y
check_success "Финальное обновление"

# === УСТАНОВКА ОСНОВНЫХ ПАКЕТОВ ===
PACKAGES="pavucontrol r7-office yandex-browser-stable sshfs pinta perl-Getopt-Long perl-File-Copy"
dnf install -y $PACKAGES
check_success "Установка основных пакетов"

# Установка MAX
dnf install -y max
check_success "Установка MAX"

# Установка локальных RPM
if ls *.rpm 1> /dev/null 2>&1; then
    dnf install -y *.rpm
    check_success "Установка локальных RPM"
fi

# === УСТАНОВКА VIPNET ===
if confirm_installation "ViPNet"; then
    install_vipnet
else
    echo -e "${YELLOW}Пропускаем установку ViPNet${NC}"
fi

# === НАСТРОЙКА DNS ДЛЯ VIPNET (ТОЛЬКО ДЛЯ ДЕПАРТАМЕНТА ОБРАЗОВАНИЯ) ===
echo -e "${GREEN}=== Настройка DNS для ViPNet ===${NC}"
echo -e "${YELLOW}Внимание! Замена DNS на корпоративные (10.13.60.2, 10.14.100.222)${NC}"
echo -e "${YELLOW}необходима ТОЛЬКО для работы в локальной сети департамента образования.${NC}"
echo -e "${YELLOW}Если вы работаете в другой сети или через интернет, оставьте DNS без изменений.${NC}"
echo -e "${YELLOW}Заменить DNS на корпоративные? (y/n)${NC}"
read -r configure_dns

if [[ $configure_dns =~ ^[Yy]$ ]]; then
    setup_vipnet_dns
else
    echo -e "${YELLOW}Пропускаем настройку DNS. DNS-серверы остаются без изменений.${NC}"
fi

# === УСТАНОВКА КРИПТОПРО И ДОПОЛНИТЕЛЬНЫХ ПАКЕТОВ ===
if confirm_installation "КриптоПро и дополнительные пакеты"; then
    echo -e "${GREEN}Установка КриптоПро и дополнительных пакетов...${NC}"
    
    dnf install -y ifd-rutokens
    check_success "Установка ifd-rutokens"
    
    dnf install -y token-manager
    check_success "Установка token-manager"
    
    dnf install -y gostcryptogui caja-gostcryptogui
    check_success "Установка gostcryptogui и caja-gostcryptogui"
    
    if [ -f "$WORK_DIR/R4/install_gui.sh" ]; then
        chmod +x "$WORK_DIR/R4/install_gui.sh"
        cd "$WORK_DIR/R4"
        ./install_gui.sh
        cd "$WORK_DIR"
        check_success "Установка КриптоПро"
    else
        echo -e "${YELLOW}Предупреждение: Файл install_gui.sh не найден${NC}"
    fi
else
    echo -e "${YELLOW}Пропускаем установку КриптоПро${NC}"
fi

# === УСТАНОВКА KASPERSKY AGENT ===
if confirm_installation "Kaspersky Agent"; then
    if [ -f "klnagent64-15.4.0-8952.x86_64.sh" ]; then
        chmod +x klnagent64-15.4.0-8952.x86_64.sh
        ./klnagent64-15.4.0-8952.x86_64.sh
        check_success "Установка Kaspersky Agent"
    else
        echo -e "${RED}✗ Файл klnagent64-15.4.0-8952.x86_64.sh не найден${NC}"
    fi
else
    echo -e "${YELLOW}Пропускаем установку Kaspersky Agent${NC}"
fi

# Очистка RPM пакетов
rm -f "$WORK_DIR"/*.rpm
check_success "Очистка временных файлов"

# Включение TRIM для SSD
systemctl enable --now fstrim.timer
check_success "Настройка TRIM"

# Обновление GRUB
grub2-mkconfig -o /boot/grub2/grub.cfg
check_success "Обновление GRUB"

# Установка 1С
if confirm_installation "1С"; then
    echo -e "${GREEN}Устанавливаю 1С...${NC}"
    
    case $source_choice in
        1)
            download_from_github "1c.tar.gz" "$WORK_DIR"
            ;;
        2)
            echo -e "${YELLOW}Введи пароль админа:${NC}"
            download_from_smb "10.13.60.3" "soft" "MKUUO.LBT.RF/admin" "RedOS/1c.tar.gz" "$WORK_DIR/1c.tar.gz"
            ;;
    esac
    
    if [ -f "1c.tar.gz" ]; then
        echo -e "${BLUE}Распаковка 1c.tar.gz...${NC}"
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

# Настройка для моноблока KSG
if confirm_installation "настройку для моноблока KSG"; then
    if [ -f "/etc/gdm/Init/Default" ]; then
        insert_before_exit "/etc/gdm/Init/Default" "xrandr --output HDMI-3 --primary"
        echo -e "${GREEN}✓ Настройка KSG выполнена${NC}"
    else
        echo -e "${RED}✗ Файл /etc/gdm/Init/Default не найден${NC}"
    fi
else
    echo -e "${YELLOW}Пропускаем настройку KSG${NC}"
fi

# === ЗАВЕРШЕНИЕ ===
echo -e "${GREEN}=== Настройка завершена! ===${NC}"
echo -e "${BLUE}Время завершения: $(date)${NC}"
echo -e "${BLUE}GitHub репозиторий: https://github.com/$GITHUB_USER/$GITHUB_REPO${NC}"
echo -e "${YELLOW}Рекомендуется перезагрузить систему. Перезагрузить сейчас? (y/n)${NC}"
read -r reboot_now
if [[ $reboot_now =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Перезагрузка...${NC}"
    reboot
fi