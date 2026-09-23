package cli

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestRenderStatusHumanAndJSONAgree(t *testing.T) {
	status := StatusView{Tasks: []TaskView{
		{ID: "T001", Phase: "Setup", Title: "Build core", Status: "ready"},
		{ID: "T002", Phase: "Setup", Title: "Add protocol", Status: "pending", UnsatisfiedDependencies: []string{"T001"}},
	}}
	human, err := RenderStatus(status, false)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(human, "T001") || !strings.Contains(human, "T002") || !strings.Contains(human, "T001 unsatisfied") {
		t.Fatalf("human output omitted runtime information: %q", human)
	}
	machine, err := RenderStatus(status, true)
	if err != nil {
		t.Fatal(err)
	}
	var decoded StatusView
	if err := json.Unmarshal([]byte(machine), &decoded); err != nil {
		t.Fatal(err)
	}
	if len(decoded.Tasks) != 2 || decoded.Tasks[1].Status != "pending" {
		t.Fatalf("unexpected JSON projection: %#v", decoded)
	}
}

func TestRenderMultipleSourcesAsTrees(t *testing.T) {
	view := StatusView{Sources: []StatusSource{{Path: "specs/001-demo/tasks.md", Digest: "abcdef123456", Tasks: []TaskView{{ID: "T001", Title: "Work", Status: "ready"}}}}}
	output, err := RenderStatus(view, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range []string{"specs/001-demo/tasks.md", "abcdef123456", "(1 tasks)", "T001", "READY", "Work"} {
		if !strings.Contains(output, value) {
			t.Fatalf("output missing %q: %s", value, output)
		}
	}
	encoded, err := RenderStatus(view, true)
	if err != nil {
		t.Fatal(err)
	}
	var decoded StatusView
	if err := json.Unmarshal([]byte(encoded), &decoded); err != nil || len(decoded.Sources) != 1 {
		t.Fatalf("invalid source JSON: %s (%v)", encoded, err)
	}
}

func TestRenderTaskShowIncludesExecutionDetail(t *testing.T) {
	view := TaskView{ID: "T023", Phase: "Parser", Title: "Implement parser", Status: "running", Agent: "pi", CurrentAction: "editing parser"}
	output, err := RenderTask(view, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{"T023", "running", "pi", "editing parser"} {
		if !strings.Contains(output, expected) {
			t.Fatalf("task output missing %q: %q", expected, output)
		}
	}
}
