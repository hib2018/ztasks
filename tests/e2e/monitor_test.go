package e2e_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
)

type statusResult struct {
	Sources []struct {
		Path   string `json:"path"`
		Digest string `json:"digest"`
		Tasks  []struct {
			ID string `json:"id"`
		} `json:"tasks"`
	} `json:"sources"`
	Tasks []struct {
		ID                      string   `json:"id"`
		Title                   string   `json:"title"`
		Status                  string   `json:"status"`
		UnsatisfiedDependencies []string `json:"unsatisfied_dependencies"`
	} `json:"tasks"`
}

func TestCrossBinaryMonitorRegeneratesDigestBoundArtifactWithoutChangingSource(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	sourcePath := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(sourcePath), 0o755); err != nil {
		t.Fatal(err)
	}
	source := []byte("# Tasks\n\n## Phase 1: Demo\n\n- [ ] T001 Base\n- [ ] T002 Dependent (depends on T001)\n- [ ] T003 Independent\n")
	if err := os.WriteFile(sourcePath, source, 0o644); err != nil {
		t.Fatal(err)
	}

	statusBytes := runFrontend(t, root, project, "status", "--json")
	assertMonitorProjection(t, statusBytes)
	after, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(source, after) {
		t.Fatal("status changed canonical tasks.md bytes")
	}

	digest := sha256.Sum256(source)
	artifactPath := filepath.Join(project, ".ztasks", "sources", hex.EncodeToString(digest[:]), "dependencies.json")
	firstArtifact, err := os.ReadFile(artifactPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(artifactPath); err != nil {
		t.Fatal(err)
	}
	runFrontend(t, root, project, "task", "show", "T002", "--json")
	regenerated, err := os.ReadFile(artifactPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(firstArtifact, regenerated) {
		t.Fatal("regenerated dependency artifact is not deterministic")
	}

	changed := bytes.Replace(source, []byte("Independent"), []byte("Independent changed"), 1)
	if err := os.WriteFile(sourcePath, changed, 0o644); err != nil {
		t.Fatal(err)
	}
	changedStatus := runFrontend(t, root, project, "status", "--json")
	if !bytes.Contains(changedStatus, []byte("Independent changed")) {
		t.Fatal("monitor reused a stale source artifact")
	}
	changedDigest := sha256.Sum256(changed)
	changedArtifact := filepath.Join(project, ".ztasks", "sources", hex.EncodeToString(changedDigest[:]), "dependencies.json")
	if _, err := os.Stat(changedArtifact); err != nil {
		t.Fatal("changed source did not create a digest-bound artifact")
	}
}

func TestStatusListsMultipleTaskSources(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	for index, path := range []string{"specs/001-demo/tasks.md", "specs/004-look/tasks.md"} {
		full := filepath.Join(project, path)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("## Phase\n- [ ] T001 Task "+string(rune('A'+index))+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	encoded := runFrontend(t, root, project, "status", "--json")
	var status statusResult
	if err := json.Unmarshal(encoded, &status); err != nil {
		t.Fatal(err)
	}
	if len(status.Sources) != 2 || status.Sources[0].Path != "specs/001-demo/tasks.md" || status.Sources[1].Path != "specs/004-look/tasks.md" {
		t.Fatalf("unexpected multi-source status: %s", encoded)
	}
	for _, source := range status.Sources {
		if len(source.Digest) < 12 || len(source.Tasks) != 1 {
			t.Fatalf("unexpected source: %#v", source)
		}
	}
}

func assertMonitorProjection(t *testing.T, encoded []byte) {
	t.Helper()
	var status statusResult
	if err := json.Unmarshal(encoded, &status); err != nil {
		t.Fatal(err)
	}
	if len(status.Tasks) != 3 {
		t.Fatalf("task count = %d", len(status.Tasks))
	}
	if status.Tasks[0].Status != "ready" || status.Tasks[1].Status != "pending" || status.Tasks[2].Status != "ready" {
		t.Fatalf("unexpected readiness: %#v", status.Tasks)
	}
	if len(status.Tasks[1].UnsatisfiedDependencies) != 1 || status.Tasks[1].UnsatisfiedDependencies[0] != "T001" {
		t.Fatalf("unexpected dependencies: %#v", status.Tasks[1].UnsatisfiedDependencies)
	}
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot resolve repository root")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filename), "..", ".."))
}

func build(t *testing.T, root string) {
	t.Helper()
	command := exec.Command("make", "build")
	command.Dir = root
	command.Env = append(os.Environ(),
		"GOCACHE="+filepath.Join(root, ".go-build-cache"),
		"ZIG_GLOBAL_CACHE_DIR="+filepath.Join(root, ".zig-global-cache"),
	)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("build failed: %v\n%s", err, output)
	}
}

func runFrontend(t *testing.T, root, project string, arguments ...string) []byte {
	t.Helper()
	command := exec.Command(filepath.Join(root, "dist", "ztasks"), arguments...)
	command.Dir = project
	command.Env = append(os.Environ(), "ZTASKS_CORE="+filepath.Join(root, "core", "zig-out", "bin", "ztasks-core"))
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("ztasks failed: %v\n%s", err, output)
	}
	return output
}
