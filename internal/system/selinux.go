package system

import (
    "os"
    "strings"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func DisableSELinux() error {
    configPath := "/etc/selinux/config"
    
    // Проверяем существует ли файл
    if _, err := os.Stat(configPath); os.IsNotExist(err) {
        logger.Debug("Файл %s не найден, SELinux возможно не установлен", configPath)
        return nil
    }
    
    // Читаем файл
    data, err := os.ReadFile(configPath)
    if err != nil {
        return err
    }
    
    content := string(data)
    
    // Проверяем текущее состояние
    if strings.Contains(content, "SELINUX=disabled") {
        logger.Debug("SELinux уже отключен")
        return nil
    }
    
    // Отключаем SELinux
    newContent := strings.Replace(content, "SELINUX=enforcing", "SELINUX=disabled", -1)
    newContent = strings.Replace(newContent, "SELINUX=permissive", "SELINUX=disabled", -1)
    
    if err := os.WriteFile(configPath, []byte(newContent), 0644); err != nil {
        return err
    }
    
    logger.Success("SELinux отключен (требуется перезагрузка для полного применения)")
    
    return nil
}

func SetSELinuxMode(mode string) error {
    configPath := "/etc/selinux/config"
    
    data, err := os.ReadFile(configPath)
    if err != nil {
        return err
    }
    
    content := string(data)
    newContent := strings.Replace(content, "SELINUX=disabled", "SELINUX="+mode, -1)
    
    if err := os.WriteFile(configPath, []byte(newContent), 0644); err != nil {
        return err
    }
    
    logger.Success("SELinux установлен в режим: %s", mode)
    
    return nil
}