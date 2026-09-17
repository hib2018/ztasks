package coreclient

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverCorePrefersBundledLibexecAndHonorsExplicitOverride(t *testing.T) {
	prefix := t.TempDir()
	frontend := filepath.Join(prefix, "bin", "ztasks")
	bundled := filepath.Join(prefix, "libexec", "ztasks", "ztasks-core")
	override := filepath.Join(prefix, "custom-core")
	for _, path := range []string{frontend, bundled, override} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("binary"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := DiscoverCore(frontend, ""); err != nil || got != bundled {
		t.Fatalf("bundled discovery = %q, %v", got, err)
	}
	if got, err := DiscoverCore(frontend, override); err != nil || got != override {
		t.Fatalf("override discovery = %q, %v", got, err)
	}
}

func TestDiscoverCoreExplainsMissingComponent(t *testing.T) {
	_, err := DiscoverCore(filepath.Join(t.TempDir(), "bin", "ztasks"), "")
	if !errors.Is(err, ErrCoreNotFound) {
		t.Fatalf("error = %v", err)
	}
}
