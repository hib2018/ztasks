package e2e_test

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestExecutionPersistsReplaysAndUnlocksDependencies(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)

	start := runFrontend(t, root, project, "start", "T001", "--json")
	assertResultStatus(t, start, "task.started", "running")
	progress := runFrontend(t, root, project, "event", "emit", "--type", "task.progress", "--task", "T001", "--message", "editing-parser", "--json")
	assertResultStatus(t, progress, "task.progress", "running")
	complete := runFrontend(t, root, project, "complete", "T001", "done", "--json")
	assertResultStatus(t, complete, "task.completed", "completed")

	status := runFrontend(t, root, project, "status", "--json")
	var decoded statusResult
	if err := json.Unmarshal(status, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.Tasks[0].Status != "completed" || decoded.Tasks[1].Status != "ready" {
		t.Fatalf("restart replay did not unlock dependency: %#v", decoded.Tasks)
	}
	events, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Count(events, []byte{'\n'}) != 3 || events[len(events)-1] != '\n' {
		t.Fatalf("event log is not complete JSONL: %q", events)
	}
	if _, err := os.Stat(filepath.Join(project, ".ztasks", "state.json")); err != nil {
		t.Fatal("snapshot was not written after committed event")
	}
}

func TestExecutionRequestRetryIsIdempotentAndConflictIsRejected(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)
	request := `{"version":1,"request_id":"req-fixed","op":"task.start","actor":{"kind":"human","id":"operator"},"task_id":"T001","payload":{}}`
	conflict := `{"version":1,"request_id":"req-fixed","op":"task.block","actor":{"kind":"human","id":"operator"},"task_id":"T001","payload":{"reason":"different"}}`
	responses := runCoreLines(t, root, project, request, request, conflict)
	if len(responses) != 3 {
		t.Fatalf("response count = %d", len(responses))
	}
	var first, retry struct {
		Result struct {
			Event struct {
				Sequence uint64 `json:"seq"`
			} `json:"event"`
		} `json:"result"`
	}
	if err := json.Unmarshal(responses[0], &first); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(responses[1], &retry); err != nil {
		t.Fatal(err)
	}
	if first.Result.Event.Sequence != 1 || retry.Result.Event.Sequence != 1 {
		t.Fatalf("retry appended another event: first=%d retry=%d", first.Result.Event.Sequence, retry.Result.Event.Sequence)
	}
	if !bytes.Contains(responses[2], []byte("idempotency_conflict")) {
		t.Fatalf("conflicting request identity was not rejected: %s", responses[2])
	}
	events, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Count(events, []byte{'\n'}) != 1 {
		t.Fatalf("idempotent retry changed durable log: %q", events)
	}
}

func executionProject(t *testing.T) string {
	t.Helper()
	project := t.TempDir()
	target := filepath.Join(project, "specs", "001-demo", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(filepath.Join(repositoryRoot(t), "protocol", "fixtures", "speckit", "dependencies", "exact", "tasks.md"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, source, 0o644); err != nil {
		t.Fatal(err)
	}
	return project
}

func assertResultStatus(t *testing.T, encoded []byte, eventType, status string) {
	t.Helper()
	var response struct {
		Event struct {
			Type string `json:"type"`
		} `json:"event"`
		Runtime struct {
			Status string `json:"status"`
		} `json:"runtime"`
	}
	if err := json.Unmarshal(encoded, &response); err != nil {
		t.Fatal(err)
	}
	if response.Event.Type != eventType || response.Runtime.Status != status {
		t.Fatalf("unexpected result: %#v", response)
	}
}

func runCoreLines(t *testing.T, root, project string, lines ...string) [][]byte {
	t.Helper()
	command := exec.Command(filepath.Join(root, "core", "zig-out", "bin", "ztasks-core"), "serve", "--project-root", project)
	command.Stdin = bytes.NewBufferString(stringsJoinLines(lines))
	output, err := command.Output()
	if err != nil {
		t.Fatal(err)
	}
	var responses [][]byte
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		responses = append(responses, bytes.Clone(scanner.Bytes()))
	}
	return responses
}

func stringsJoinLines(lines []string) string {
	var buffer bytes.Buffer
	for _, line := range lines {
		buffer.WriteString(line)
		buffer.WriteByte('\n')
	}
	return buffer.String()
}
