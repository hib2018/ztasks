package e2e_test

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestFiveHundredTasksAndTenThousandEventsRenderWithinTwoSeconds(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := t.TempDir()
	sourcePath := filepath.Join(project, "specs", "001-large", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(sourcePath), 0o755); err != nil {
		t.Fatal(err)
	}
	source, err := os.Create(sourcePath)
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintln(source, "## Phase 1")
	for index := 1; index <= 500; index++ {
		fmt.Fprintf(source, "- [ ] T%03d Task %d\n", index, index)
	}
	if err := source.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(project, ".ztasks"), 0o755); err != nil {
		t.Fatal(err)
	}
	log, err := os.Create(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	writer := bufio.NewWriterSize(log, 1<<20)
	for sequence := 1; sequence <= 10_000; sequence++ {
		event, _ := json.Marshal(map[string]any{"version": 1, "event_id": fmt.Sprintf("evt-%d", sequence), "seq": sequence, "request_id": fmt.Sprintf("req-%d", sequence), "timestamp": "2026-01-01T00:00:00Z", "actor": map[string]any{"kind": "human", "id": "fixture"}, "type": "task.comment", "task_id": "T001", "session_id": nil, "payload": map[string]any{"message": "progress"}, "status_after": "ready", "attempt_after": 0, "redactions": []any{}})
		record, _ := json.Marshal(map[string]any{"seq": sequence, "request_id": fmt.Sprintf("req-%d", sequence), "semantic_hash": "fixture", "event_json": string(event)})
		writer.Write(record)
		writer.WriteByte('\n')
	}
	writer.Flush()
	log.Close()
	started := time.Now()
	result := runFrontend(t, root, project, "status", "--json")
	if elapsed := time.Since(started); elapsed > 2*time.Second {
		t.Fatalf("status took %s", elapsed)
	}
	var status statusResult
	if err := json.Unmarshal(result, &status); err != nil || len(status.Tasks) != 500 {
		t.Fatalf("unexpected result: tasks=%d err=%v", len(status.Tasks), err)
	}
}
