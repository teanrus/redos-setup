package installer

import (
    "fmt"
    "os"
    "path/filepath"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installFonts() error {
    logger.Info("Установка шрифтов Liberation...")
    
    // Устанавливаем unzip если нужно
    if err := i.runCommand("dnf", "install", "-y", "unzip"); err != nil {
        logger.Warn("Не удалось установить unzip: %v", err)
    }
    
    // Пробуем скачать .zip (новый формат)
    fileName := "Liberation.zip"
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    
    if err != nil {
        // Пробуем старый формат .tar.gz
        fileName = "Liberation.tar.gz"
        filePath, err = i.downloader.DownloadFile(fileName, i.workDir)
        if err != nil {
            return fmt.Errorf("ошибка загрузки шрифтов Liberation: %v", err)
        }
        
        // Распаковка .tar.gz
        if err := i.runCommand("tar", "-xzf", filePath, "-C", i.workDir); err != nil {
            return fmt.Errorf("ошибка распаковки шрифтов: %v", err)
        }
        
        // Копируем шрифты
        fontsDir := "/usr/share/fonts/liberation"
        if err := os.MkdirAll(fontsDir, 0755); err != nil {
            return fmt.Errorf("ошибка создания директории шрифтов: %v", err)
        }
        
        liberationDir := filepath.Join(i.workDir, "Liberation")
        if err := i.runCommand("cp", "-r", liberationDir+"/.", fontsDir+"/"); err != nil {
            return fmt.Errorf("ошибка копирования шрифтов: %v", err)
        }
        
        os.RemoveAll(liberationDir)
        
    } else {
        // Распаковка .zip
        if err := i.runCommand("unzip", "-o", filePath, "-d", "/usr/share/fonts/liberation"); err != nil {
            return fmt.Errorf("ошибка распаковки шрифтов: %v", err)
        }
    }
    
    // Обновляем кэш шрифтов
    if err := i.runCommand("fc-cache", "-fv"); err != nil {
        logger.Warn("Ошибка обновления кэша шрифтов: %v", err)
    }
    
    // Очистка
    i.downloader.Cleanup(filePath)
    
    logger.Success("Шрифты Liberation установлены")
    return nil
}