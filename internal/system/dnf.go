package system

import (
    "os"
    "strings"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func ConfigureDNF(parallelDownloads int) error {
    configPath := "/etc/dnf/dnf.conf"
    
    // Проверяем существует ли файл
    if _, err := os.Stat(configPath); os.IsNotExist(err) {
        logger.Debug("Файл %s не найден, создаем новый", configPath)
        return createDNFConfig(parallelDownloads)
    }
    
    // Читаем файл
    data, err := os.ReadFile(configPath)
    if err != nil {
        return err
    }
    
    content := string(data)
    
    // Проверяем наличие max_parallel_downloads
    if strings.Contains(content, "max_parallel_downloads") {
        logger.Debug("DNF уже настроен")
        return nil
    }
    
    // Добавляем настройку
    f, err := os.OpenFile(configPath, os.O_APPEND|os.O_WRONLY, 0644)
    if err != nil {
        return err
    }
    defer f.Close()
    
    if _, err := f.WriteString("\nmax_parallel_downloads=10\n"); err != nil {
        return err
    }
    
    logger.Success("DNF настроен (max_parallel_downloads=10)")
    
    return nil
}

func createDNFConfig(parallelDownloads int) error {
    config := `[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=True
best=True
skip_if_unavailable=False
max_parallel_downloads=10
`
    if err := os.WriteFile("/etc/dnf/dnf.conf", []byte(config), 0644); err != nil {
        return err
    }
    
    logger.Success("Создан файл конфигурации DNF")
    return nil
}