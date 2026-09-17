package cli

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestProjectCommandsBuildExactProtocolOperations(t *testing.T) {
	initRequest := BuildProjectRequest("req-init", "init", "specs/001/tasks.md")
	if initRequest.Operation != "project.init" || !strings.Contains(string(initRequest.Payload), "specs/001/tasks.md") {
		t.Fatalf("unexpected init request: %#v", initRequest)
	}
	for command, operation := range map[string]string{"sync": "source.sync", "doctor": "health.check"} {
		request := BuildProjectRequest("req-"+command, command, "")
		if request.Operation != operation {
			t.Fatalf("%s mapped to %s", command, request.Operation)
		}
	}
}

func TestProjectResultHumanOutputIsActionable(t *testing.T) {
	result := json.RawMessage(`{"healthy":false,"diagnostics":[{"code":"history.corrupt","severity":"error","message":"Event history is corrupt"}]}`)
	output, err := RenderProjectResult("doctor", result, false)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output, "history.corrupt") || !strings.Contains(output, "Event history is corrupt") {
		t.Fatalf("diagnostic omitted: %q", output)
	}
}

func TestHelpAndVersionDoNotRequireCore(t *testing.T) {
	for _, arguments := range [][]string{{"help"}, {"version"}} {
		var stdout, stderr strings.Builder
		if code := Run(arguments, &stdout, &stderr); code != 0 {
			t.Fatalf("%v failed without core: code=%d stderr=%q", arguments, code, stderr.String())
		}
		if stdout.Len() == 0 {
			t.Fatalf("%v produced no output", arguments)
		}
	}
}
