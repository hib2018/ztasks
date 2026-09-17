package e2e_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestCommittedEventRemainsAuthoritativeWhenSnapshotWriteFails(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)
	if err := os.MkdirAll(filepath.Join(project, ".ztasks", "state.json"), 0o755); err != nil {
		t.Fatal(err)
	}
	_ = runFrontendFailure(t, root, project, "start", "T001", "--json")
	status := runFrontend(t, root, project, "status", "--json")
	if !bytes.Contains(status, []byte(`"status":"running"`)) {
		t.Fatalf("committed Event was not replayed after snapshot failure: %s", status)
	}
}

func TestArtifactWrittenBeforeEventFailureDoesNotBecomeAuthority(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)
	runFrontend(t, root, project, "init", "--json")
	eventsPath := filepath.Join(project, ".ztasks", "events.jsonl")
	before, err := os.ReadFile(eventsPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(eventsPath, 0o444); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(eventsPath, 0o644) })
	sourcePath := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.WriteFile(sourcePath, []byte("## Phase 1\n- [ ] T001 Changed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	_ = runFrontendFailure(t, root, project, "sync", "--json")
	after, err := os.ReadFile(eventsPath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("failed Event append changed authoritative history")
	}
}

func runFrontendFailure(t *testing.T, root, project string, arguments ...string) []byte {
	t.Helper()
	command := exec.Command(filepath.Join(root, "dist", "ztasks"), arguments...)
	command.Dir = project
	command.Env = append(os.Environ(), "ZTASKS_CORE="+filepath.Join(root, "core", "zig-out", "bin", "ztasks-core"))
	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatalf("ztasks unexpectedly succeeded: %s", output)
	}
	return output
}
