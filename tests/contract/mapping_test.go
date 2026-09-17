package contract_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDocumentedOperationsEventsFixturesAndCoreMappingsStayConsistent(t *testing.T) {
	root := repositoryRoot(t)
	mapping, err := os.ReadFile(filepath.Join(root, "core", "src", "application", "operation_map.zig"))
	if err != nil {
		t.Fatal(err)
	}
	contract, err := os.ReadFile(filepath.Join(root, "specs", "001-task-execution-control", "contracts", "event-mapping.md"))
	if err != nil {
		t.Fatal(err)
	}
	fixtures, err := os.ReadFile(filepath.Join(root, "protocol", "fixtures", "v1", "project.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	for operation, event := range map[string]string{"project.init": "project.initialized", "source.sync": "source.synced", "task.start": "task.started", "human.pause_request": "human.pause_requested"} {
		if !strings.Contains(string(mapping), operation) || !strings.Contains(string(mapping), strings.ReplaceAll(event, ".", "_")) {
			t.Fatalf("Core mapping missing %s -> %s", operation, event)
		}
		if !strings.Contains(string(contract), operation) || !strings.Contains(string(contract), event) {
			t.Fatalf("contract missing %s -> %s", operation, event)
		}
	}
	for _, operation := range []string{"project.init", "source.sync", "project.inspect", "health.check"} {
		if !strings.Contains(string(fixtures), `"op":"`+operation+`"`) {
			t.Fatalf("fixture missing %s", operation)
		}
	}
}
