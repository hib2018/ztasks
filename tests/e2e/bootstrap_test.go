package e2e_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestBootstrapImportsCheckedTasksAsOneAuditableEvent(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	sourcePath := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(sourcePath), 0o755); err != nil {
		t.Fatal(err)
	}
	source := []byte("## Phase 1\n- [X] T001 Base\n- [x] T002 Done (depends on T001)\n- [ ] T003 Next (depends on T002)\n")
	if err := os.WriteFile(sourcePath, source, 0o644); err != nil {
		t.Fatal(err)
	}

	result := runFrontend(t, root, project, "bootstrap", "--from-checkboxes", "--json")
	var imported struct {
		ImportedCount int `json:"imported_count"`
		Event         struct {
			Type    string `json:"type"`
			Payload struct {
				Completed []string `json:"completed"`
			} `json:"payload"`
		} `json:"event"`
	}
	if err := json.Unmarshal(result, &imported); err != nil {
		t.Fatal(err)
	}
	if imported.Event.Type != "project.runtime_bootstrapped" || imported.ImportedCount != 2 {
		t.Fatalf("unexpected bootstrap result: %s", result)
	}
	if len(imported.Event.Payload.Completed) != 2 || imported.Event.Payload.Completed[0] != "T001" || imported.Event.Payload.Completed[1] != "T002" {
		t.Fatalf("unexpected imported tasks: %#v", imported.Event.Payload.Completed)
	}

	var status statusResult
	if err := json.Unmarshal(runFrontend(t, root, project, "status", "--json"), &status); err != nil {
		t.Fatal(err)
	}
	if status.Tasks[0].Status != "completed" || status.Tasks[1].Status != "completed" || status.Tasks[2].Status != "ready" {
		t.Fatalf("unexpected restored status: %#v", status.Tasks)
	}
	events, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Count(events, []byte("\n")) != 1 {
		t.Fatalf("bootstrap must append exactly one event: %s", events)
	}
	after, err := os.ReadFile(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(source, after) {
		t.Fatal("bootstrap changed canonical tasks.md")
	}
}

func TestBootstrapRejectsCheckedTaskWithUncheckedDependency(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	sourcePath := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(sourcePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sourcePath, []byte("## Phase 1\n- [ ] T001 Base\n- [X] T002 Invalid (depends on T001)\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	runFrontendFailure(t, root, project, "bootstrap", "--from-checkboxes", "--json")
	if _, err := os.Stat(filepath.Join(project, ".ztasks", "events.jsonl")); !os.IsNotExist(err) {
		t.Fatalf("rejected bootstrap created Event history: %v", err)
	}
}
