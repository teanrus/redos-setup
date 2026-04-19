package cli

import (
    "fmt"
    
    "github.com/spf13/cobra"
    "github.com/spf13/viper"
    
    "github.com/teanrus/redos-setup/internal/installer"
    "github.com/teanrus/redos-setup/internal/logger"
    "github.com/teanrus/redos-setup/internal/system"
)

var (
    cfgFile        string
    nonInteractive bool
    autoYes        bool
    force          bool
    verbose        bool
    components     []string
    version        string
    buildDate      string
)

func Execute(v, date string) error {
    version = v
    buildDate = date
    return rootCmd.Execute()
}

var rootCmd = &cobra.Command{
    Use:   "redos-setup",
    Short: "CLI для автоматической настройки РЕД ОС 7.3/8",
    Long: `redos-setup - Инструмент для автоматической установки и настройки ПО на РЕД ОС.
    
Поддерживаемые версии: РЕД ОС 7.3, 8.0 и выше.

Примеры:
  # Интерактивный режим
  redos-setup
  
  # Установка конкретных компонентов
  redos-setup install --components telegram,vipnet,1c
  
  # Неинтерактивная установка с авто-подтверждением
  redos-setup install --yes --components base-system,telegram
  
  # Принудительная установка (игнорировать ошибки)
  redos-setup install --force --components all
  
  # Показать список компонентов
  redos-setup list
  
  # Проверить совместимость с ОС
  redos-setup check`,
}

var installCmd = &cobra.Command{
    Use:   "install",
    Short: "Установка компонентов",
    Run: func(cmd *cobra.Command, args []string) {
        if len(components) == 0 {
            logger.Error("Не указаны компоненты для установки")
            logger.Info("Используйте: redos-setup install --components telegram,vipnet")
            logger.Info("Список компонентов: redos-setup list")
            return
        }
        
        inst := installer.NewInstaller(nonInteractive, autoYes, force)
        
        if err := inst.InstallComponents(components); err != nil {
            logger.Error("Ошибка установки: %v", err)
            return
        }
        
        logger.Success("Установка завершена успешно!")
    },
}

var listCmd = &cobra.Command{
    Use:   "list",
    Short: "Список доступных компонентов",
    Run: func(cmd *cobra.Command, args []string) {
        fmt.Println("\n📦 Доступные компоненты для установки:\n")
        
        fmt.Println("🔧 Системные:")
        fmt.Println("  base-system    - Базовая система (репозитории, ядро, R7 Office, MAX)")
        fmt.Println("  trim           - Настройка TRIM для SSD")
        fmt.Println("  grub           - Обновление конфигурации GRUB")
        fmt.Println("  ksg            - Настройка моноблока KSG")
        
        fmt.Println("\n🌐 Браузеры:")
        fmt.Println("  chromium       - Chromium-GOST (с поддержкой ГОСТ)")
        fmt.Println("  yandex         - Яндекс Браузер для организаций")
        
        fmt.Println("\n💬 Мессенджеры:")
        fmt.Println("  telegram       - Telegram Desktop")
        fmt.Println("  vk             - VK Messenger")
        fmt.Println("  sreda          - Корпоративный мессенджер СРЕДА")
        
        fmt.Println("\n🛡️ Безопасность и криптография:")
        fmt.Println("  kaspersky      - Kaspersky Agent")
        fmt.Println("  cryptopro      - КриптоПро CSP")
        fmt.Println("  vipnet         - ViPNet VPN (Client или Client+DP)")
        
        fmt.Println("\n📊 Офисные и приложения:")
        fmt.Println("  1c             - 1С:Предприятие")
        fmt.Println("  fonts          - Шрифты Liberation")
        fmt.Println("  r7-office      - R7 Office")
        fmt.Println("  pavucontrol    - Микшер звука")
        fmt.Println("  sshfs          - Монтирование удаленных директорий")
        fmt.Println("  pinta          - Графический редактор")
        
        fmt.Println("\n🎯 Особые режимы:")
        fmt.Println("  all            - Установить всё доступное ПО")
        
        fmt.Println("\n💡 Использование:")
        fmt.Println("  redos-setup install --components telegram,vipnet --yes")
    },
}

var checkCmd = &cobra.Command{
    Use:   "check",
    Short: "Проверка совместимости компонентов с ОС",
    Run: func(cmd *cobra.Command, args []string) {
        osVersion, err := system.DetectOSVersion()
        if err != nil {
            logger.Error("Ошибка определения ОС: %v", err)
            return
        }
        
        fmt.Printf("\n=== Проверка совместимости ===\n")
        fmt.Printf("ОС: %s\n\n", osVersion.String())
        
        components := []string{"cryptopro", "vipnet", "kaspersky", "1c"}
        
        fmt.Println("Совместимость компонентов:\n")
        
        compatibleCount := 0
        for _, comp := range components {
            compatible, warning := osVersion.CheckComponentCompatibility(comp)
            
            if compatible {
                fmt.Printf("✅ %s: совместим\n", comp)
                compatibleCount++
            } else {
                fmt.Printf("❌ %s: НЕ СОВМЕСТИМ\n", comp)
                fmt.Printf("   %s\n", warning)
            }
        }
        
        fmt.Printf("\nСовместимо: %d из %d\n", compatibleCount, len(components))
        
        if compatibleCount < len(components) {
            fmt.Println("\n📌 Рекомендации:")
            fmt.Println("   • Используйте обновленные версии компонентов")
            fmt.Println("   • Установите компоненты через --force на свой страх и риск")
        }
        
        fmt.Println("\n📌 Рекомендуемые компоненты для вашей версии:")
        recommended := osVersion.GetRecommendedComponents()
        for _, rec := range recommended {
            fmt.Printf("   • %s\n", rec)
        }
    },
}

var versionCmd = &cobra.Command{
    Use:   "version",
    Short: "Версия CLI",
    Run: func(cmd *cobra.Command, args []string) {
        fmt.Printf("redos-setup version %s\n", version)
        fmt.Printf("Build date: %s\n", buildDate)
        fmt.Printf("GitHub: https://github.com/teanrus/redos-setup\n")
    },
}

func init() {
    cobra.OnInitialize(initConfig)
    
    // Глобальные флаги
    rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "файл конфигурации")
    rootCmd.PersistentFlags().BoolVarP(&nonInteractive, "non-interactive", "n", false, "неинтерактивный режим")
    rootCmd.PersistentFlags().BoolVarP(&autoYes, "yes", "y", false, "автоматически подтверждать все запросы")
    rootCmd.PersistentFlags().BoolVarP(&force, "force", "f", false, "принудительная установка (игнорировать ошибки)")
    rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "подробный вывод")
    
    // Флаги для install команды
    installCmd.Flags().StringSliceVarP(&components, "components", "c", []string{}, "компоненты для установки (через запятую)")
    
    // Добавляем команды
    rootCmd.AddCommand(installCmd, listCmd, checkCmd, versionCmd)
}

func initConfig() {
    if verbose {
        logger.SetVerbose(true)
    }
    
    if cfgFile != "" {
        viper.SetConfigFile(cfgFile)
    } else {
        viper.SetConfigName("config")
        viper.SetConfigType("yaml")
        viper.AddConfigPath("/etc/redos-setup/")
        viper.AddConfigPath("$HOME/.config/redos-setup/")
        viper.AddConfigPath(".")
    }
    
    viper.SetDefault("github.user", "teanrus")
    viper.SetDefault("github.repo", "redos-setup")
    viper.SetDefault("paths.work_dir", "/home/inst")
    
    if err := viper.ReadInConfig(); err != nil {
        if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
            fmt.Printf("Ошибка чтения конфигурации: %v\n", err)
        }
    }
}