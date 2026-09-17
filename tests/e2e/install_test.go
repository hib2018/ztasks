package e2e_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestCleanPrefixInstallationNeedsNoProjectToolchainAndIsolatesProjects(t *testing.T) {
	root := repositoryRoot(t)
	packageCommand := exec.Command(filepath.Join(root, "scripts", "package.sh"), runtime.GOOS, runtime.GOARCH)
	packageCommand.Dir = root
	packageCommand.Env = append(os.Environ(), "GOCACHE="+filepath.Join(root, ".go-build-cache"), "ZIG_GLOBAL_CACHE_DIR="+filepath.Join(root, ".zig-global-cache"))
	output, err := packageCommand.CombinedOutput()
	if err != nil {
		t.Fatalf("package failed: %v\n%s", err, output)
	}
	archive := strings.TrimSpace(string(output))
	prefix := filepath.Join(t.TempDir(), "prefix")
	install := exec.Command(filepath.Join(root, "scripts", "install.sh"), "install", prefix, archive)
	if output, err := install.CombinedOutput(); err != nil {
		t.Fatalf("install failed: %v\n%s", err, output)
	}
	frontend := filepath.Join(prefix, "bin", "ztasks")
	for _, project := range []string{filepath.Join(t.TempDir(), "one"), filepath.Join(t.TempDir(), "two")} {
		source := filepath.Join(project, "specs", "001-demo", "tasks.md")
		if err := os.MkdirAll(filepath.Dir(source), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(source, []byte("## Phase 1\n- [ ] T001 Work\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		command := exec.Command(frontend, "init", "--json")
		command.Dir = project
		command.Env = []string{"PATH=/usr/bin:/bin"}
		if output, err := command.CombinedOutput(); err != nil {
			t.Fatalf("installed run failed: %v\n%s", err, output)
		}
		if _, err := os.Stat(filepath.Join(project, ".ztasks", "events.jsonl")); err != nil {
			t.Fatal(err)
		}
	}
}
