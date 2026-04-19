package system

import (
    "bufio"
    "fmt"
    "os"
    "os/exec"
    "regexp"
    "strconv"
    "strings"
    
    "github.com/teanrus/redos-setup/internal/logger"
)

type OSVersion struct {
    Major     int
    Minor     int
    Patch     int
    Full      string
    Name      string
    IsRedOS   bool
    IsAstra   bool
    IsAlterOS bool
    Arch      string
}

type ComponentCompatibility struct {
    Component         string
    MinVersion        int
    MaxVersion        int
    AlternativeVersion string
    Warning           string
    Blocking          bool
}

var (
    componentCompatibility = map[string]ComponentCompatibility{
        "cryptopro": {
            Component:         "КриптоПро CSP",
            MinVersion:        7,
            MaxVersion:        8,
            AlternativeVersion: "5.0.128",
            Warning:           "Для РЕД ОС 8 требуется КриптоПро версии 5.0.128 и выше",
            Blocking:          false,
        },
        "vipnet": {
            Component:         "ViPNet VPN",
            MinVersion:        7,
            MaxVersion:        8,
            AlternativeVersion: "4.16.0",
            Warning:           "Для РЕД ОС 8 требуется ViPNet версии 4.16.0 и выше",
            Blocking:          false,
        },
        "kaspersky": {
            Component:         "Kaspersky Agent",
            MinVersion:        7,
            MaxVersion:        8,
            AlternativeVersion: "14.0.0",
            Warning:           "Для РЕД ОС 8 требуется Kaspersky Agent версии 14.0 и выше",
            Blocking:          false,
        },
        "1c": {
            Component:         "1С:Предприятие",
            MinVersion:        7,
            MaxVersion:        8,
            AlternativeVersion: "8.3.25",
            Warning:           "Для РЕД ОС 8 рекомендуется версия 1С 8.3.25 и выше",
            Blocking:          false,
        },
    }
)

func DetectOSVersion() (*OSVersion, error) {
    logger.Info("Определение версии операционной системы...")
    
    osInfo := &OSVersion{
        Arch: getArch(),
    }
    
    // Пробуем прочитать /etc/os-release
    if err := readOSRelease(osInfo); err == nil && osInfo.Major > 0 {
        logger.Success("Определена ОС: %s %s (%s)", osInfo.Name, osInfo.Full, osInfo.Arch)
        return osInfo, nil
    }
    
    // Альтернативный метод через RPM
    if err := detectByRPM(osInfo); err == nil && osInfo.Major > 0 {
        logger.Success("Определена ОС (RPM): %s %s (%s)", osInfo.Name, osInfo.Full, osInfo.Arch)
        return osInfo, nil
    }
    
    return nil, fmt.Errorf("не удалось определить версию ОС")
}

func readOSRelease(osInfo *OSVersion) error {
    file, err := os.Open("/etc/os-release")
    if err != nil {
        return err
    }
    defer file.Close()
    
    scanner := bufio.NewScanner(file)
    for scanner.Scan() {
        line := scanner.Text()
        
        if strings.HasPrefix(line, "NAME=") {
            name := strings.Trim(strings.TrimPrefix(line, "NAME="), "\"")
            osInfo.Name = name
            if strings.Contains(name, "РЕД ОС") || strings.Contains(name, "RED OS") {
                osInfo.IsRedOS = true
            } else if strings.Contains(name, "Astra") {
                osInfo.IsAstra = true
            } else if strings.Contains(name, "AlterOS") {
                osInfo.IsAlterOS = true
            }
        }
        
        if strings.HasPrefix(line, "VERSION_ID=") {
            versionStr := strings.Trim(strings.TrimPrefix(line, "VERSION_ID="), "\"")
            osInfo.Full = versionStr
            parseVersion(versionStr, osInfo)
        }
    }
    
    if osInfo.Major == 0 {
        return fmt.Errorf("версия не найдена")
    }
    
    return nil
}

func detectByRPM(osInfo *OSVersion) error {
    // Пробуем через rpm -q redos-release
    cmd := exec.Command("rpm", "-q", "redos-release")
    output, err := cmd.Output()
    if err == nil {
        outputStr := string(output)
        re := regexp.MustCompile(`(\d+)\.(\d+)`)
        matches := re.FindStringSubmatch(outputStr)
        if len(matches) == 3 {
            major, _ := strconv.Atoi(matches[1])
            minor, _ := strconv.Atoi(matches[2])
            osInfo.Major = major
            osInfo.Minor = minor
            osInfo.Full = fmt.Sprintf("%d.%d", major, minor)
            osInfo.IsRedOS = true
            osInfo.Name = "РЕД ОС"
            return nil
        }
    }
    
    return fmt.Errorf("не удалось определить через RPM")
}

func parseVersion(versionStr string, osInfo *OSVersion) {
    parts := strings.Split(versionStr, ".")
    if len(parts) > 0 {
        osInfo.Major, _ = strconv.Atoi(parts[0])
    }
    if len(parts) > 1 {
        osInfo.Minor, _ = strconv.Atoi(parts[1])
    }
    if len(parts) > 2 {
        osInfo.Patch, _ = strconv.Atoi(parts[2])
    }
}

func getArch() string {
    cmd := exec.Command("uname", "-m")
    output, err := cmd.Output()
    if err != nil {
        return "unknown"
    }
    return strings.TrimSpace(string(output))
}

func (os *OSVersion) CheckComponentCompatibility(component string) (bool, string) {
    compat, exists := componentCompatibility[component]
    if !exists {
        return true, ""
    }
    
    if os.Major >= compat.MinVersion && os.Major <= compat.MaxVersion {
        return true, ""
    }
    
    warning := fmt.Sprintf("⚠️  %s\n", compat.Warning)
    warning += fmt.Sprintf("   Текущая версия ОС: %s %s\n", os.Name, os.Full)
    warning += fmt.Sprintf("   Рекомендуемая версия компонента: %s\n", compat.AlternativeVersion)
    
    if compat.Blocking {
        warning += fmt.Sprintf("   ❌ Установка заблокирована из-за несовместимости\n")
    } else {
        warning += fmt.Sprintf("   ⚠️  Установка возможна, но не гарантируется стабильная работа\n")
    }
    
    return false, warning
}

func (os *OSVersion) GetIncompatibleComponents(components []string) []string {
    var incompatible []string
    for _, comp := range components {
        compatible, _ := os.CheckComponentCompatibility(comp)
        if !compatible {
            incompatible = append(incompatible, comp)
        }
    }
    return incompatible
}

func (os *OSVersion) FilterComponentsByVersion(components []string, interactive bool) ([]string, error) {
    var filtered []string
    var warnings []string
    
    for _, comp := range components {
        compatible, warning := os.CheckComponentCompatibility(comp)
        
        if compatible {
            filtered = append(filtered, comp)
        } else {
            warnings = append(warnings, warning)
            
            if interactive {
                fmt.Printf("\n%s\n", warning)
                fmt.Print("Продолжить установку этого компонента? (y/N): ")
                var answer string
                fmt.Scanln(&answer)
                
                if strings.ToLower(answer) == "y" || strings.ToLower(answer) == "yes" {
                    logger.Warn("Пользователь подтвердил установку %s на несовместимую ОС", comp)
                    filtered = append(filtered, comp)
                } else {
                    logger.Info("Пропускаем компонент %s", comp)
                }
            } else {
                logger.Warn("Пропускаем %s: несовместим с %s %s", comp, os.Name, os.Full)
            }
        }
    }
    
    if len(warnings) > 0 && len(filtered) < len(components) {
        logger.Warn("Некоторые компоненты были пропущены из-за несовместимости")
    }
    
    return filtered, nil
}

func (os *OSVersion) GetRecommendedComponents() []string {
    recommended := []string{"base-system", "fonts", "trim", "grub"}
    
    if os.Major == 7 {
        recommended = append(recommended, "telegram", "chromium", "yandex", "1c")
    } else if os.Major == 8 {
        recommended = append(recommended, "telegram", "chromium")
        logger.Info("Для РЕД ОС 8 рекомендуется устанавливать КриптоПро 5.0+ и ViPNet 4.16+ отдельно")
    }
    
    return recommended
}

func (os *OSVersion) String() string {
    return fmt.Sprintf("%s %s (%s)", os.Name, os.Full, os.Arch)
}