package cli

import (
	"strings"
	"testing"
)

func TestHumanInterventionCommandsMapToRequestOperations(t *testing.T) {
	cases := map[string]string{
		"pause": "human.pause_request", "resume": "human.resume_request", "retry": "human.retry_request",
		"stop": "human.stop_request", "skip": "human.skip_request", "inspect": "human.inspect_request", "comment": "human.comment",
	}
	for command, operation := range cases {
		request, err := BuildInterventionRequest("req-1", command, "T001", "please inspect")
		if err != nil {
			t.Fatal(err)
		}
		if request.Operation != operation || request.Actor.Kind != "human" {
			t.Fatalf("unexpected request for %s: %#v", command, request)
		}
	}
}

func TestSuccessfulHumanRequestSaysRequestedNotConfirmed(t *testing.T) {
	output := RenderInterventionAccepted("T001", "pause")
	if !strings.Contains(output, "requested") || strings.Contains(output, "paused") || strings.Contains(output, "stopped") {
		t.Fatalf("ambiguous intervention wording: %q", output)
	}
}
