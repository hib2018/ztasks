package cli

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

type recordingCaller struct {
	ops          []string
	initialized  bool
	sourceDigest string
}

func (c *recordingCaller) Call(request protocol.Request) (protocol.Response, error) {
	c.ops = append(c.ops, request.Operation)
	if request.Operation == "project.inspect" {
		result, _ := json.Marshal(map[string]any{"initialized": c.initialized, "source_digest": c.sourceDigest})
		return protocol.Response{Version: protocol.Version, RequestID: request.RequestID, OK: true, Result: result}, nil
	}
	if request.Operation == "source.sync" {
		result, _ := json.Marshal(map[string]any{"event": map[string]string{"type": "source.synced"}})
		return protocol.Response{Version: protocol.Version, RequestID: request.RequestID, OK: true, Result: result}, nil
	}
	return protocol.Response{Version: protocol.Version, RequestID: request.RequestID, OK: false}, nil
}

func TestAutoSyncChangedSourceSyncsSingleInitializedSource(t *testing.T) {
	root := t.TempDir()
	writeTaskSource(t, root)

	caller := &recordingCaller{initialized: true, sourceDigest: "sha256:old"}
	notice, err := autoSyncChangedSource(root, caller, "req")
	if err != nil {
		t.Fatal(err)
	}
	if notice != "Sync complete: tasks.md changed" {
		t.Fatalf("notice = %q", notice)
	}
	if len(caller.ops) != 2 || caller.ops[0] != "project.inspect" || caller.ops[1] != "source.sync" {
		t.Fatalf("unexpected operations: %#v", caller.ops)
	}
}

func TestAutoSyncChangedSourceReportsSkippedUninitialized(t *testing.T) {
	root := t.TempDir()
	writeTaskSource(t, root)

	caller := &recordingCaller{}
	notice, err := autoSyncChangedSource(root, caller, "req")
	if err != nil {
		t.Fatal(err)
	}
	if notice != "Sync skipped: project not initialized. Press b to bootstrap from checkboxes." {
		t.Fatalf("notice = %q", notice)
	}
}

func writeTaskSource(t *testing.T, root string) {
	t.Helper()
	path := filepath.Join(root, "specs", "001", "tasks.md")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("## Phase\n- [ ] T001 Work\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}
