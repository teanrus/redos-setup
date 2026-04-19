package installer

import (
    "fmt"
    "os"
    "os/exec"
    "strings"
    "time"
    
    "github.com/teanrus/redos-setup/internal/logger"
    "github.com/teanrus/redos-setup/internal/system"
)

type Installer struct {
    nonInteractive bool
    autoYes        bool
    force          bool
    workDir        string
    osVersion      *system.OSVersion
}

func NewInstaller(nonInteractive, autoYes, force bool) *Installer {
    return &Installer{
        nonInteractive: nonInteractive,
        autoYes:        autoYes,
        force:          force,
        workDir:        "/home/inst",
    }
}

func (i *Installer) InstallComponents(components []string) error {
    startTime := time.Now()
    
    if os.Geteuid() != 0 {
        return fmt.Errorf("скрипт должен запускаться с правами root (используйте sudo)")
    }
    
    var err error
    i.osVersion, err = system.DetectOSVersion()
    if err != nil {
        logger.Warn("Не удалось определить версию ОС: %v", err)
        i.osVersion = &system.OSVersion{Major: 7, Minor: 3, IsRedOS: true}
    }
    
    i.printOSInfo()
    
    filteredComponents, err := i.osVersion.FilterComponentsByVersion(components, !i.nonInteractive)
    if err != nil {
        return err
    }
    
    if len(filteredComponents) == 0 {
        return fmt.Errorf("нет совместимых компонентов для установки")
    }
    
    logger.Step("Инициализация системы")
    if err := i.initSystem(); err != nil {
        logger.Warn("Некоторые инициализации не удались: %v", err)
    }
    
    successCount := 0
    failCount := 0
    
    for idx, component := range filteredComponents {
        logger.Step("[%d/%d] Установка: %s", idx+1, len(filteredComponents), component)
        
        if err := i.installComponent(strings.TrimSpace(component)); err != nil {
            logger.Error("Ошибка установки %s: %v", component, err)
            failCount++
            if !i.nonInteractive && !i.force {
                return err
            }
        } else {
            successCount++
        }
    }
    
    duration := time.Since(startTime)
    logger.Step("Установка завершена за %v", duration.Round(time.Second))
    logger.Info("Успешно установлено: %d", successCount)
    if failCount > 0 {
        logger.Warn("Ошибок: %d", failCount)
    }
    
    i.printFinalRecommendations()
    
    return nil
}

func (i *Installer) printOSInfo() {
    logger.Step("Информация об операционной системе")
    logger.Info("%s", i.osVersion.String())
    
    if i.osVersion.Major >= 8 {
        logger.Warn("Обнаружена РЕД ОС 8.x")
        logger.Warn("Проверьте совместимость компонентов перед установкой")
    }
    
    if !i.osVersion.IsRedOS {
        logger.Warn("Система не определена как РЕД ОС")
        logger.Warn("Скрипт разработан для РЕД ОС 7.3+, возможны проблемы")
    }
    
    fmt.Println()
}

func (i *Installer) printFinalRecommendations() {
    logger.Step("Рекомендации после установки")
    
    fmt.Println("\n📌 Для всех версий РЕД ОС:")
    fmt.Println("   • Выполните перезагрузку системы: sudo reboot")
    fmt.Println("   • Проверьте работу установленных компонентов")
    fmt.Println("   • При проблемах проверьте логи: /var/log/redos-setup/")
    
    if i.osVersion.Major >= 8 {
        fmt.Println("\n📌 Специально для РЕД ОС 8:")
        fmt.Println("   • КриптоПро: проверьте версию: /opt/cprocsp/sbin/amd64/cpconfig -ver")
        fmt.Println("   • ViPNet: проверьте версию: vipnet-client --version")
    }
    
    fmt.Println()
}

func (i *Installer) initSystem() error {
    if err := system.DisableSELinux(); err != nil {
        logger.Warn("Не удалось отключить SELinux: %v", err)
    }
    
    if err := system.ConfigureDNF(10); err != nil {
        logger.Warn("Не удалось настроить DNF: %v", err)
    }
    
    if err := os.MkdirAll(i.workDir, 0755); err != nil {
        return fmt.Errorf("не удалось создать рабочую директорию: %v", err)
    }
    
    logger.Success("Система инициализирована")
    return nil
}

func (i *Installer) installComponent(component string) error {
    switch component {
    case "base-system":
        return i.installBaseSystem()
    case "telegram":
        return i.installTelegram()
    case "vipnet":
        return i.installVipNet()
    case "1c", "1с":
        return i.install1C()
    case "cryptopro":
        return i.installCryptoPro()
    case "kaspersky":
        return i.installKaspersky()
    case "chromium":
        return i.installChromium()
    case "yandex", "yandex-browser":
        return i.installYandexBrowser()
    case "sreda":
        return i.installSreda()
    case "vk", "vk-messenger":
        return i.installVK()
    case "fonts":
        return i.installFonts()
    case "trim":
        return i.setupTRIM()
    case "grub":
        return i.updateGRUB()
    case "ksg":
        return i.setupKSG()
    case "all":
        return i.installAll()
    default:
        return fmt.Errorf("неизвестный компонент: %s", component)
    }
}

func (i *Installer) runCommand(name string, args ...string) error {
    logger.Debug("Выполнение команды: %s %v", name, args)
    
    cmd := exec.Command(name, args...)
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    
    if err := cmd.Run(); err != nil {
        return fmt.Errorf("ошибка выполнения команды: %v", err)
    }
    
    return nil
}

func (i *Installer) runCommandWithOutput(name string, args ...string) (string, error) {
    logger.Debug("Выполнение команды: %s %v", name, args)
    
    cmd := exec.Command(name, args...)
    output, err := cmd.CombinedOutput()
    
    if err != nil {
        return string(output), fmt.Errorf("ошибка выполнения команды: %v\n%s", err, output)
    }
    
    return string(output), nil
}


