package e2e_test

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestInterventionPauseAndRetryWorkflow(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)

	first := runFrontend(t, root, project, "start", "T001", "--json")
	assertAttempt(t, first, "task.started", "running", 1)
	runFrontend(t, root, project, "fail", "T001", "compiler failed", "--json")

	direct := exec.Command(filepath.Join(root, "dist", "ztasks"), "start", "T001", "--json")
	direct.Dir = project
	direct.Env = append(os.Environ(), "ZTASKS_CORE="+filepath.Join(root, "core", "zig-out", "bin", "ztasks-core"))
	if output, err := direct.CombinedOutput(); err == nil || !bytes.Contains(output, []byte("invalid_transition")) {
		t.Fatalf("failed task restarted without retry correlation: err=%v output=%s", err, output)
	}

	retry := runFrontend(t, root, project, "retry", "T001", "--json")
	assertAttempt(t, retry, "human.retry_requested", "failed", 1)
	second := runFrontend(t, root, project, "start", "T001", "--json")
	assertAttempt(t, second, "task.started", "running", 2)

	started := time.Now()
	pause := runFrontend(t, root, project, "pause", "T001", "--json")
	if elapsed := time.Since(started); elapsed >= 30*time.Second {
		t.Fatalf("pause request took %s; expected under 30 seconds", elapsed)
	}
	assertAttempt(t, pause, "human.pause_requested", "running", 2)
}

func assertAttempt(t *testing.T, encoded []byte, eventType, status string, attempt int) {
	t.Helper()
	var result struct {
		Event struct {
			Type string `json:"type"`
		} `json:"event"`
		Runtime struct {
			Status  string `json:"status"`
			Attempt int    `json:"attempt"`
		} `json:"runtime"`
	}
	if err := json.Unmarshal(encoded, &result); err != nil {
		t.Fatal(err)
	}
	if result.Event.Type != eventType || result.Runtime.Status != status || result.Runtime.Attempt != attempt {
		t.Fatalf("unexpected intervention result: %#v", result)
	}
}
