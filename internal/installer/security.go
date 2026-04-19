package installer

import (
    "fmt"
    "os"
    "path/filepath"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installKaspersky() error {
    logger.Info("Установка Kaspersky Agent...")
    
    var fileName string
    if i.osVersion.Major >= 8 {
        fileName = "kasp_14.0_redos8.tar.gz"
        logger.Warn("Устанавливается Kaspersky Agent 14.0 для РЕД ОС 8")
    } else {
        fileName = "kasp.tar.gz"
    }
    
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки Kaspersky Agent: %v", err)
    }
    
    // Распаковываем
    if err := i.runCommand("tar", "-xzf", filePath, "-C", i.workDir); err != nil {
        return fmt.Errorf("ошибка распаковки Kaspersky Agent: %v", err)
    }
    
    // Ищем и запускаем скрипты установки
    files, err := os.ReadDir(i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка чтения директории: %v", err)
    }
    
    installed := false
    for _, file := range files {
        if filepath.Ext(file.Name()) == ".sh" {
            scriptPath := filepath.Join(i.workDir, file.Name())
            if err := os.Chmod(scriptPath, 0755); err != nil {
                logger.Warn("Не удалось сделать скрипт исполняемым: %v", err)
                continue
            }
            
            if err := i.runCommand(scriptPath); err != nil {
                logger.Warn("Ошибка выполнения скрипта %s: %v", file.Name(), err)
            } else {
                installed = true
            }
        }
    }
    
    if !installed {
        logger.Warn("Не найдены скрипты установки Kaspersky Agent")
    }
    
    // Очистка
    i.downloader.Cleanup(filePath)
    for _, file := range files {
        if filepath.Ext(file.Name()) == ".sh" {
            os.Remove(filepath.Join(i.workDir, file.Name()))
        }
    }
    
    logger.Success("Kaspersky Agent установлен")
    return nil
}

func (i *Installer) installCryptoPro() error {
    logger.Info("Установка КриптоПро CSP...")
    
    // Устанавливаем зависимости
    deps := []string{"ifd-rutokens", "token-manager", "gostcryptogui", "caja-gostcryptogui"}
    for _, dep := range deps {
        logger.Info("Установка зависимости: %s", dep)
        if err := i.runCommand("dnf", "install", "-y", dep); err != nil {
            logger.Warn("Не удалось установить %s: %v", dep, err)
        }
    }
    
    var fileName string
    if i.osVersion.Major >= 8 {
        fileName = "cryptopro_5.0_redos8.tar.gz"
        logger.Warn("Устанавливается КриптоПро 5.0 для РЕД ОС 8")
    } else {
        fileName = "kriptopror4.tar.gz"
    }
    
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки КриптоПро: %v", err)
    }
    
    // Распаковываем
    if err := i.runCommand("tar", "-xzf", filePath, "-C", i.workDir); err != nil {
        return fmt.Errorf("ошибка распаковки КриптоПро: %v", err)
    }
    
    // Ищем установщик
    installed := false
    
    // Пробуем разные варианты установщиков
    installers := []string{
        "install_gui.sh",
        "install.sh",
        "csp/install.sh",
        "linux-amd64/install.sh",
    }
    
    for _, installer := range installers {
        installerPath := filepath.Join(i.workDir, installer)
        if _, err := os.Stat(installerPath); err == nil {
            if err := os.Chmod(installerPath, 0755); err == nil {
                if err := i.runCommand(installerPath); err == nil {
                    installed = true
                    break
                }
            }
        }
    }
    
    if !installed {
        // Устанавливаем RPM пакеты вручную
        files, _ := os.ReadDir(i.workDir)
        for _, file := range files {
            if filepath.Ext(file.Name()) == ".rpm" {
                rpmPath := filepath.Join(i.workDir, file.Name())
                i.runCommand("dnf", "install", "-y", rpmPath)
            }
        }
    }
    
    // Очистка
    i.downloader.Cleanup(filePath)
    
    logger.Success("КриптоПро CSP установлен")
    return nil
}