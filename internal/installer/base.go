package installer

import (
    "fmt"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installBaseSystem() error {
    logger.Step("Установка базовой системы")
    
    // 1. Обновление системы
    logger.Info("Обновление системы...")
    if err := i.runCommand("dnf", "clean", "all"); err != nil {
        logger.Warn("Ошибка очистки кэша: %v", err)
    }
    
    if err := i.runCommand("dnf", "makecache"); err != nil {
        logger.Warn("Ошибка обновления кэша: %v", err)
    }
    
    if err := i.runCommand("dnf", "update", "-y"); err != nil {
        return fmt.Errorf("ошибка обновления системы: %v", err)
    }
    logger.Success("Система обновлена")
    
    // 2. Установка репозиториев
    logger.Info("Установка репозиториев...")
    
    repos := []string{"r7-release", "yandex-browser-release"}
    for _, repo := range repos {
        logger.Info("Установка репозитория: %s", repo)
        if err := i.runCommand("dnf", "install", "-y", repo); err != nil {
            logger.Warn("Не удалось установить %s: %v", repo, err)
        }
    }
    
    // 3. Установка MAX репозитория
    logger.Info("Установка MAX репозитория...")
    maxRepo := `[max]
name=MAX Desktop
baseurl=https://download.max.ru/linux/rpm/el/9/x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://download.max.ru/linux/rpm/public.asc
sslverify=1
metadata_expire=300
`
    if err := i.runCommand("bash", "-c", fmt.Sprintf("echo '%s' > /etc/yum.repos.d/max.repo", maxRepo)); err != nil {
        logger.Warn("Не удалось создать max.repo: %v", err)
    }
    
    if err := i.runCommand("rpm", "--import", "https://download.max.ru/linux/rpm/public.asc"); err != nil {
        logger.Warn("Не удалось импортировать ключ MAX: %v", err)
    }
    
    // 4. Установка ядра
    logger.Info("Установка ядра redos-kernels6...")
    if err := i.runCommand("dnf", "install", "-y", "redos-kernels6-release"); err != nil {
        logger.Warn("Не удалось установить ядро: %v", err)
    }
    
    // 5. Финальное обновление
    logger.Info("Финальное обновление...")
    if err := i.runCommand("dnf", "update", "-y"); err != nil {
        logger.Warn("Ошибка финального обновления: %v", err)
    }
    
    // 6. Установка основных пакетов
    logger.Info("Установка основных пакетов...")
    
    packages := []string{
        "pavucontrol",
        "r7-office",
        "yandex-browser-stable",
        "sshfs",
        "pinta",
        "perl-Getopt-Long",
        "perl-File-Copy",
    }
    
    // Добавляем MAX для РЕД ОС 7
    if i.osVersion.Major == 7 {
        packages = append(packages, "max")
    }
    
    for _, pkg := range packages {
        logger.Info("Установка пакета: %s", pkg)
        if err := i.runCommand("dnf", "install", "-y", pkg); err != nil {
            logger.Warn("Не удалось установить %s: %v", pkg, err)
        }
    }
    
    // Для РЕД ОС 8 MAX устанавливаем отдельно
    if i.osVersion.Major >= 8 {
        if err := i.installMAX(); err != nil {
            logger.Warn("Ошибка установки MAX: %v", err)
        }
    }
    
    logger.Success("Базовая система установлена")
    return nil
}

func (i *Installer) installR7Office() error {
    logger.Info("Установка R7 Office...")
    
    if err := i.runCommand("dnf", "install", "-y", "r7-office"); err != nil {
        return fmt.Errorf("ошибка установки R7 Office: %v", err)
    }
    
    logger.Success("R7 Office установлен")
    return nil
}

func (i *Installer) installMAX() error {
    logger.Info("Установка MAX Desktop...")
    
    if i.osVersion.Major >= 8 {
        // Для РЕД ОС 8 используем прямую установку
        if err := i.runCommand("dnf", "install", "-y", 
            "https://download.max.ru/linux/rpm/el/9/x86_64/max-1.0-1.el9.x86_64.rpm"); err != nil {
            return fmt.Errorf("ошибка установки MAX: %v", err)
        }
    } else {
        if err := i.runCommand("dnf", "install", "-y", "max"); err != nil {
            return fmt.Errorf("ошибка установки MAX: %v", err)
        }
    }
    
    logger.Success("MAX Desktop установлен")
    return nil
}

func (i *Installer) installPavucontrol() error {
    logger.Info("Установка Pavucontrol (микшер звука)...")
    
    if err := i.runCommand("dnf", "install", "-y", "pavucontrol"); err != nil {
        return fmt.Errorf("ошибка установки Pavucontrol: %v", err)
    }
    
    logger.Success("Pavucontrol установлен")
    return nil
}

func (i *Installer) installSSHFS() error {
    logger.Info("Установка SSHFS...")
    
    if err := i.runCommand("dnf", "install", "-y", "sshfs"); err != nil {
        return fmt.Errorf("ошибка установки SSHFS: %v", err)
    }
    
    logger.Success("SSHFS установлен")
    return nil
}

func (i *Installer) installPinta() error {
    logger.Info("Установка Pinta...")
    
    if err := i.runCommand("dnf", "install", "-y", "pinta"); err != nil {
        return fmt.Errorf("ошибка установки Pinta: %v", err)
    }
    
    logger.Success("Pinta установлен")
    return nil
}