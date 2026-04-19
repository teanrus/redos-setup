package main

import (
    "os"
    
    "github.com/teanrus/redos-setup/internal/logger"
    "github.com/teanrus/redos-setup/pkg/cli"
)

var version = "3.0.0"
var buildDate = "unknown"

func main() {
    // Инициализация логгера
    if err := logger.Init(); err != nil {
        println("Ошибка инициализации логгера:", err.Error())
        os.Exit(1)
    }
    defer logger.Close()
    
    // Запуск CLI
    if err := cli.Execute(version, buildDate); err != nil {
        logger.Error("Ошибка: %v", err)
        os.Exit(1)
    }
}