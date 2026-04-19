package downloader

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"github.com/teanrus/redos-setup/internal/logger"
)

type Downloader struct {
	githubUser string
	githubRepo string
	client     *http.Client
}

func NewDownloader(user, repo string) *Downloader {
	return &Downloader{
		githubUser: user,
		githubRepo: repo,
		client:     &http.Client{},
	}
}

func (d *Downloader) DownloadFile(fileName, destDir string) (string, error) {
	url := fmt.Sprintf("https://github.com/%s/%s/releases/latest/download/%s",
		d.githubUser, d.githubRepo, fileName)

	logger.Info("Загрузка: %s", fileName)

	resp, err := d.client.Get(url)
	if err != nil {
		return "", fmt.Errorf("ошибка запроса: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP ошибка: %s", resp.Status)
	}

	if err := os.MkdirAll(destDir, 0755); err != nil {
		return "", fmt.Errorf("ошибка создания директории: %v", err)
	}

	filePath := filepath.Join(destDir, fileName)
	file, err := os.Create(filePath)
	if err != nil {
		return "", fmt.Errorf("ошибка создания файла: %v", err)
	}
	defer file.Close()

	written, err := io.Copy(file, resp.Body)
	if err != nil {
		return "", fmt.Errorf("ошибка записи файла: %v", err)
	}

	logger.Debug("Загружено %d байт", written)
	logger.Success("Файл загружен: %s", fileName)

	return filePath, nil
}

func (d *Downloader) Cleanup(filePath string) {
	if err := os.Remove(filePath); err != nil {
		logger.Debug("Не удалось удалить %s: %v", filePath, err)
	} else {
		logger.Debug("Удален временный файл: %s", filePath)
	}
}
