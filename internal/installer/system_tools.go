package installer

import (
    "fmt"
    "os"
    "strings"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) setupTRIM() error {
    logger.Info("Настройка TRIM для SSD...")
    
    if err := i.runCommand("systemctl", "enable", "--now", "fstrim.timer"); err != nil {
        return fmt.Errorf("ошибка настройки TRIM: %v", err)
    }
    
    logger.Success("TRIM настроен")
    return nil
}

func (i *Installer) updateGRUB() error {
    logger.Info("Обновление конфигурации GRUB...")
    
    if err := i.runCommand("grub2-mkconfig", "-o", "/boot/grub2/grub.cfg"); err != nil {
        return fmt.Errorf("ошибка обновления GRUB: %v", err)
    }
    
    logger.Success("GRUB обновлен")
    return nil
}

func (i *Installer) setupKSG() error {
    logger.Info("Настройка для моноблока KSG...")
    
    gdmFile := "/etc/gdm/Init/Default"
    
    // Проверяем существует ли файл
    if _, err := os.Stat(gdmFile); os.IsNotExist(err) {
        return fmt.Errorf("файл %s не найден", gdmFile)
    }
    
    // Читаем файл
    content, err := os.ReadFile(gdmFile)
    if err != nil {
        return fmt.Errorf("ошибка чтения %s: %v", gdmFile, err)
    }
    
    // Проверяем, нет ли уже такой строки
    if strings.Contains(string(content), "xrandr --output HDMI-3 --primary") {
        logger.Info("Настройка KSG уже применена")
        return nil
    }
    
    // Добавляем строку перед exit 0
    lines := strings.Split(string(content), "\n")
    newContent := ""
    
    for _, line := range lines {
        if strings.Contains(line, "exit 0") {
            newContent += "xrandr --output HDMI-3 --primary\n"
        }
        newContent += line + "\n"
    }
    
    // Записываем обратно
    if err := os.WriteFile(gdmFile, []byte(newContent), 0755); err != nil {
        return fmt.Errorf("ошибка записи %s: %v", gdmFile, err)
    }
    
    logger.Success("Настройка KSG выполнена")
    return nil
}

func (i *Installer) installAll() error {
    logger.Step("Установка ВСЕХ компонентов")
    
    components := []string{
        "base-system",
        "fonts",
        "chromium",
        "yandex",
        "sreda",
        "vk",
        "telegram",
        "kaspersky",
        "cryptopro",
        "vipnet",
        "1c",
        "trim",
        "grub",
        "ksg",
    }
    
    for _, component := range components {
        if err := i.installComponent(component); err != nil {
            logger.Error("Ошибка установки %s: %v", component, err)
            if !i.force {
                return err
            }
        }
    }
    
    logger.Success("Все компоненты установлены")
    return nil
}