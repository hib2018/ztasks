package coreclient

import (
	"errors"
	"os"
	"path/filepath"
)

var ErrCoreNotFound = errors.New("ztasks Core not found; reinstall the ztasks archive or set ZTASKS_CORE")

func DiscoverCore(frontendPath, override string) (string, error) {
	if override != "" {
		if executableFile(override) {
			return override, nil
		}
		return "", ErrCoreNotFound
	}
	root := filepath.Dir(filepath.Dir(frontendPath))
	candidates := []string{
		filepath.Join(root, "libexec", "ztasks", "ztasks-core"),
		filepath.Join(filepath.Dir(frontendPath), "ztasks-core"),
	}
	for _, candidate := range candidates {
		if executableFile(candidate) {
			return candidate, nil
		}
	}
	return "", ErrCoreNotFound
}

func executableFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular() && info.Mode().Perm()&0o111 != 0
}
