package installer

import (
    "fmt"
    "os"
    "path/filepath"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installTelegram() error {
    logger.Info("Установка Telegram...")
    
    // Скачиваем архив
    fileName := "tsetup.tar.xz"
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки Telegram: %v", err)
    }
    
    // Распаковываем
    if err := i.runCommand("tar", "-xJf", filePath, "-C", i.workDir); err != nil {
        return fmt.Errorf("ошибка распаковки Telegram: %v", err)
    }
    
    // Создаем директорию /opt/telegram
    telegramDir := "/opt/telegram"
    if err := os.MkdirAll(telegramDir, 0755); err != nil {
        return fmt.Errorf("ошибка создания директории %s: %v", telegramDir, err)
    }
    
    // Копируем файлы
    sourceDir := filepath.Join(i.workDir, "Telegram")
    if err := i.runCommand("cp", "-r", sourceDir+"/.", telegramDir+"/"); err != nil {
        return fmt.Errorf("ошибка копирования Telegram: %v", err)
    }
    
    // Создаем симлинк
    if err := i.runCommand("ln", "-sf", filepath.Join(telegramDir, "Telegram"), "/usr/bin/telegram"); err != nil {
        logger.Warn("Не удалось создать симлинк: %v", err)
    }
    
    // Создаем .desktop файл
    desktopFile := `[Desktop Entry]
Name=Telegram
Comment=Telegram Desktop
Exec=/opt/telegram/Telegram
Icon=/opt/telegram/telegram.png
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
`
    desktopPath := "/usr/share/applications/telegram.desktop"
    if err := os.WriteFile(desktopPath, []byte(desktopFile), 0644); err != nil {
        logger.Warn("Не удалось создать .desktop файл: %v", err)
    }
    
    // Очистка
    i.downloader.Cleanup(filePath)
    os.RemoveAll(sourceDir)
    
    logger.Success("Telegram установлен")
    return nil
}

func (i *Installer) installSreda() error {
    logger.Info("Установка мессенджера СРЕДА...")
    
    fileName := "sreda.rpm"
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки СРЕДА: %v", err)
    }
    
    if err := i.runCommand("dnf", "install", "-y", filePath); err != nil {
        return fmt.Errorf("ошибка установки СРЕДА: %v", err)
    }
    
    i.downloader.Cleanup(filePath)
    
    logger.Success("СРЕДА установлен")
    return nil
}

func (i *Installer) installVK() error {
    logger.Info("Установка VK Messenger...")
    
    fileName := "vk-messenger.rpm"
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки VK Messenger: %v", err)
    }
    
    if err := i.runCommand("dnf", "install", "-y", filePath); err != nil {
        return fmt.Errorf("ошибка установки VK Messenger: %v", err)
    }
    
    i.downloader.Cleanup(filePath)
    
    logger.Success("VK Messenger установлен")
    return nil
}