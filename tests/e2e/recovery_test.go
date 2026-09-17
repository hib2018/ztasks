package e2e_test

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestProjectSyncAuditsChangesMissingReappearanceAndNoChange(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	sourcePath := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(sourcePath), 0o755); err != nil {
		t.Fatal(err)
	}
	initial := []byte("## Phase 1\n- [ ] T001 Base\n- [ ] T002 Original\n")
	if err := os.WriteFile(sourcePath, initial, 0o644); err != nil {
		t.Fatal(err)
	}
	assertProjectEvent(t, runFrontend(t, root, project, "init", "--json"), "project.initialized", nil)

	changed := []byte("## Phase 1\n- [ ] T001 Changed\n- [ ] T003 Added\n")
	if err := os.WriteFile(sourcePath, changed, 0o644); err != nil {
		t.Fatal(err)
	}
	assertProjectEvent(t, runFrontend(t, root, project, "sync", "--json"), "source.synced", map[string]string{"changed": "T001", "missing": "T002", "added": "T003"})

	reappeared := []byte("## Phase 1\n- [ ] T001 Changed\n- [ ] T002 Original\n- [ ] T003 Added\n")
	if err := os.WriteFile(sourcePath, reappeared, 0o644); err != nil {
		t.Fatal(err)
	}
	assertProjectEvent(t, runFrontend(t, root, project, "sync", "--json"), "source.synced", map[string]string{"reappeared": "T002"})
	assertProjectEvent(t, runFrontend(t, root, project, "sync", "--json"), "source.synced", map[string]string{})

	before, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(sourcePath, []byte("## Phase 1\n- [ ] T001 First\n- [ ] T001 Duplicate\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	commandOutput := runFrontendFailure(t, root, project, "sync", "--json")
	if !bytes.Contains(commandOutput, []byte("source")) && !bytes.Contains(commandOutput, []byte("io_error")) {
		t.Fatalf("rejected sync was not actionable: %s", commandOutput)
	}
	after, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("rejected sync changed authoritative Event history")
	}
}

func assertProjectEvent(t *testing.T, document []byte, eventType string, expected map[string]string) {
	t.Helper()
	var result struct {
		Event struct {
			Type    string         `json:"type"`
			Payload map[string]any `json:"payload"`
		} `json:"event"`
	}
	if err := json.Unmarshal(document, &result); err != nil {
		t.Fatal(err)
	}
	if result.Event.Type != eventType {
		t.Fatalf("event type = %q, document=%s", result.Event.Type, document)
	}
	for field, taskID := range expected {
		values, ok := result.Event.Payload[field].([]any)
		if !ok {
			t.Fatalf("payload %s missing: %#v", field, result.Event.Payload)
		}
		found := false
		for _, value := range values {
			if value == taskID {
				found = true
			}
		}
		if !found {
			t.Fatalf("payload %s does not contain %s: %#v", field, taskID, values)
		}
	}
}
