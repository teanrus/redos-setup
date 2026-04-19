package installer

import (
    "bufio"
    "fmt"
    "os"
    "path/filepath"
    "strings"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

func (i *Installer) installVipNet() error {
    logger.Step("Установка ViPNet")
    
    // Выбор версии
    var version string
    
    if i.nonInteractive {
        version = "1"
        logger.Info("Неинтерактивный режим: выбрана версия Client")
    } else {
        fmt.Println("\n=== Выбор версии ViPNet ===")
        if i.osVersion.Major >= 8 {
            logger.Warn("Для РЕД ОС 8 рекомендуется версия 4.16+")
        }
        fmt.Println("1. ViPNet Client (без деловой почты)")
        fmt.Println("2. ViPNet + Деловая почта (DP)")
        fmt.Print("Выберите вариант (1 или 2): ")
        
        reader := bufio.NewReader(os.Stdin)
        version, _ = reader.ReadString('\n')
        version = strings.TrimSpace(version)
    }
    
    var fileName string
    
    switch version {
    case "1":
        if i.osVersion.Major >= 8 {
            fileName = "vipnet_4.16_redos8.rpm"
            logger.Info("Установка ViPNet Client 4.16 для РЕД ОС 8")
        } else {
            fileName = "vipnetclient-gui_gost_ru_x86-64_4.15.0-26717.rpm"
        }
        
        filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
        if err != nil {
            return fmt.Errorf("ошибка загрузки ViPNet Client: %v", err)
        }
        
        if err := i.runCommand("dnf", "install", "-y", filePath); err != nil {
            return fmt.Errorf("ошибка установки ViPNet Client: %v", err)
        }
        
        i.downloader.Cleanup(filePath)
        
    case "2":
        if i.osVersion.Major >= 8 {
            fileName = "vipnet_dp_4.16_redos8.tar.gz"
        } else {
            fileName = "VipNet-DP.tar.gz"
        }
        
        filePath, err := i.downloader.DownloadFile(fileName, i.workDir)
        if err != nil {
            return fmt.Errorf("ошибка загрузки ViPNet DP: %v", err)
        }
        
        // Распаковываем
        if err := i.runCommand("tar", "-xzf", filePath, "-C", i.workDir); err != nil {
            return fmt.Errorf("ошибка распаковки ViPNet DP: %v", err)
        }
        
        // Устанавливаем все RPM
        rpmDir := strings.TrimSuffix(fileName, ".tar.gz")
        rpmPath := filepath.Join(i.workDir, rpmDir)
        
        files, _ := os.ReadDir(rpmPath)
        for _, file := range files {
            if strings.HasSuffix(file.Name(), ".rpm") {
                fullPath := filepath.Join(rpmPath, file.Name())
                i.runCommand("dnf", "install", "-y", fullPath)
            }
        }
        
        // Очистка
        i.downloader.Cleanup(filePath)
        os.RemoveAll(rpmPath)
        
    default:
        return fmt.Errorf("неверный выбор версии")
    }
    
    logger.Success("ViPNet установлен")
    return nil
}