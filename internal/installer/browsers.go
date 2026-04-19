package installer

import (
    "fmt"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installYandexBrowser() error {
    logger.Info("Установка Яндекс.Браузера...")
    
    // Репозиторий уже должен быть установлен в base-system
    if err := i.runCommand("dnf", "install", "-y", "yandex-browser-stable"); err != nil {
        return fmt.Errorf("ошибка установки Яндекс.Браузера: %v", err)
    }
    
    logger.Success("Яндекс.Браузер установлен")
    return nil
}

func (i *Installer) installChromium() error {
    logger.Info("Установка Chromium-GOST (с поддержкой ГОСТ)...")
    
    // Скачиваем RPM с GitHub
    fileName := "chromium-gost-139.0.7258.139-linux-amd64.rpm"
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки Chromium-GOST: %v", err)
    }
    
    // Устанавливаем RPM
    if err := i.runCommand("dnf", "install", "-y", filePath); err != nil {
        return fmt.Errorf("ошибка установки Chromium-GOST: %v", err)
    }
    
    // Удаляем загруженный файл
    i.downloader.Cleanup(filePath)
    
    logger.Success("Chromium-GOST установлен")
    return nil
}