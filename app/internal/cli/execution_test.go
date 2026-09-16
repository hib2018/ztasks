package cli

import "testing"

func TestExecutionCommandsMapToAllowlistedOperations(t *testing.T) {
	cases := map[string]string{
		"start": "task.start", "block": "task.block", "fail": "task.fail", "complete": "task.complete",
	}
	for command, operation := range cases {
		request, err := BuildExecutionRequest("req-1", command, "T001", "message", "agent-1", "run-1")
		if err != nil {
			t.Fatal(err)
		}
		if request.Operation != operation {
			t.Fatalf("%s mapped to %s", command, request.Operation)
		}
	}
}

func TestEventEmitAllowsOnlyExecutionAndResponseTypes(t *testing.T) {
	for _, eventType := range []string{"task.progress", "task.paused", "task.resumed", "task.blocked", "task.failed", "task.completed", "task.skipped", "task.comment", "intervention.responded"} {
		if _, err := EventEmitOperation(eventType); err != nil {
			t.Fatalf("%s rejected: %v", eventType, err)
		}
	}
	for _, eventType := range []string{"project.initialized", "source.synced", "human.pause_requested", "unknown.event"} {
		if _, err := EventEmitOperation(eventType); err == nil {
			t.Fatalf("%s should be rejected", eventType)
		}
	}
}

func TestEventListRequestIsReadOnly(t *testing.T) {
	request := BuildEventListRequest("req-1", "T001")
	if request.Operation != "event.list" || request.TaskID != "T001" {
		t.Fatalf("unexpected request: %#v", request)
	}
}
