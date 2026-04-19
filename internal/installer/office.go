package installer

import (
    "fmt"
    "os"
    "path/filepath"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) install1C() error {
    logger.Info("Установка 1С:Предприятие...")
    
    var fileName string
    if i.osVersion.Major >= 8 {
        fileName = "1c_8.3.25_redos8.tar.gz"
        logger.Warn("Устанавливается 1С 8.3.25 для РЕД ОС 8")
    } else {
        fileName = "1c.tar.gz"
    }
    
    filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка загрузки 1С: %v", err)
    }
    
    // Распаковываем
    if err := i.runCommand("tar", "-xzf", filePath, "-C", i.workDir); err != nil {
        return fmt.Errorf("ошибка распаковки 1С: %v", err)
    }
    
    // Ищем директорию с установщиком
    files, err := os.ReadDir(i.workDir)
    if err != nil {
        return fmt.Errorf("ошибка чтения директории: %v", err)
    }
    
    var installDir string
    for _, file := range files {
        if file.IsDir() && (file.Name() == "lin_8_3_24_1691" || file.Name() == "1c_install") {
            installDir = filepath.Join(i.workDir, file.Name())
            break
        }
    }
    
    if installDir == "" {
        return fmt.Errorf("не найдена директория с установщиком 1С")
    }
    
    // Запускаем установку
    installerPath := filepath.Join(installDir, "setup-full-8.3.24.1691-x86_64.run")
    if _, err := os.Stat(installerPath); err == nil {
        if err := os.Chmod(installerPath, 0755); err != nil {
            return fmt.Errorf("ошибка установки прав: %v", err)
        }
        
        // Запускаем в неинтерактивном режиме
        if err := i.runCommand(installerPath, "--mode", "unattended"); err != nil {
            logger.Warn("Unattended режим не удался, пробуем обычный: %v", err)
            if err := i.runCommand(installerPath); err != nil {
                return fmt.Errorf("ошибка установки 1С: %v", err)
            }
        }
    }
    
    // Применяем фиксы
    fixPath := filepath.Join(installDir, "fix.sh")
    if _, err := os.Stat(fixPath); err == nil {
        if err := os.Chmod(fixPath, 0755); err == nil {
            i.runCommand(fixPath)
        }
    }
    
    // Очистка
    i.downloader.Cleanup(filePath)
    os.RemoveAll(installDir)
    
    logger.Success("1С:Предприятие установлен")
    return nil
}