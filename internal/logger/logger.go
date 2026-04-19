package logger

import (
    "fmt"
    "io"
    "os"
    "path/filepath"
    "runtime"
    "strings"
    "time"
    
    "github.com/fatih/color"
)

var (
    logFile     *os.File
    fileWriter  io.Writer
    verbose     bool
    
    infoColor   = color.New(color.FgCyan).SprintFunc()
    successColor = color.New(color.FgGreen).SprintFunc()
    warnColor   = color.New(color.FgYellow).SprintFunc()
    errorColor  = color.New(color.FgRed).SprintFunc()
    debugColor  = color.New(color.FgHiBlack).SprintFunc()
)

func Init() error {
    // Создаем директорию для логов
    logDir := "/var/log/redos-setup"
    if err := os.MkdirAll(logDir, 0755); err != nil {
        // Пробуем в домашнюю директорию
        homeDir, _ := os.UserHomeDir()
        logDir = filepath.Join(homeDir, ".local", "log", "redos-setup")
        if err := os.MkdirAll(logDir, 0755); err != nil {
            return err
        }
    }
    
    // Открываем файл лога
    logPath := filepath.Join(logDir, fmt.Sprintf("redos-setup-%s.log", 
        time.Now().Format("20060102-150405")))
    
    var err error
    logFile, err = os.Create(logPath)
    if err != nil {
        return err
    }
    
    fileWriter = logFile
    Info("Лог-файл: %s", logPath)
    
    return nil
}

func SetVerbose(v bool) {
    verbose = v
}

func Close() {
    if logFile != nil {
        logFile.Close()
    }
}

func Info(format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("[%s] %s\n", infoColor("INFO"), msg)
    logToFile("INFO", msg)
}

func Success(format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("[%s] %s\n", successColor("OK"), successColor(msg))
    logToFile("SUCCESS", msg)
}

func Warn(format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("[%s] %s\n", warnColor("WARN"), warnColor(msg))
    logToFile("WARN", msg)
}

func Error(format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("[%s] %s\n", errorColor("ERROR"), errorColor(msg))
    logToFile("ERROR", msg)
}

func Debug(format string, args ...interface{}) {
    if !verbose {
        return
    }
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("[%s] %s\n", debugColor("DEBUG"), msg)
    logToFile("DEBUG", msg)
}

func Step(format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    fmt.Printf("\n━━━ %s ━━━\n", msg)
    logToFile("STEP", msg)
}

func Progress(current, total int, format string, args ...interface{}) {
    msg := fmt.Sprintf(format, args...)
    percent := float64(current) / float64(total) * 100
    bar := createProgressBar(percent)
    fmt.Printf("\r[%s] %s %3.0f%%", bar, msg, percent)
    if current == total {
        fmt.Println()
    }
    logToFile("PROGRESS", fmt.Sprintf("%s (%.0f%%)", msg, percent))
}

func createProgressBar(percent float64) string {
    width := 40
    filled := int(float64(width) * percent / 100)
    bar := strings.Repeat("█", filled) + strings.Repeat("░", width-filled)
    return bar
}

func logToFile(level, msg string) {
    if fileWriter != nil {
        timestamp := time.Now().Format("2006-01-02 15:04:05")
        
        // Получаем информацию о caller
        _, file, line, ok := runtime.Caller(3)
        if ok {
            file = filepath.Base(file)
            fmt.Fprintf(fileWriter, "[%s] %s [%s:%d]: %s\n", timestamp, level, file, line, msg)
        } else {
            fmt.Fprintf(fileWriter, "[%s] %s: %s\n", timestamp, level, msg)
        }
    }
}