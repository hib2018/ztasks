package agent

import (
	"context"
	"testing"
)

type fixtureAdapter struct {
	capabilities map[Action]bool
	result       Result
}

func (adapter fixtureAdapter) Name() string { return "fixture" }
func (adapter fixtureAdapter) Capabilities(context.Context) (Capabilities, error) {
	return Capabilities{Actions: adapter.capabilities}, nil
}
func (adapter fixtureAdapter) Apply(context.Context, Request) (Result, error) {
	return adapter.result, nil
}

func TestAdapterConformanceSupportedRejectedAndUnsupported(t *testing.T) {
	cases := []struct {
		name    string
		result  Result
		outcome Outcome
	}{
		{name: "supported", result: Result{Outcome: Acknowledged, Summary: "pause signal delivered"}, outcome: Acknowledged},
		{name: "rejected", result: Result{Outcome: Rejected, Summary: "session is already complete"}, outcome: Rejected},
		{name: "unsupported", result: Result{Outcome: Unsupported, Summary: "adapter cannot pause this harness"}, outcome: Unsupported},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			adapter := fixtureAdapter{capabilities: map[Action]bool{Pause: test.outcome != Unsupported}, result: test.result}
			result, err := ApplyConformant(context.Background(), adapter, Request{Action: Pause, TaskID: "T001", RequestEventID: "evt-1"})
			if err != nil {
				t.Fatal(err)
			}
			if result.Outcome != test.outcome {
				t.Fatalf("outcome = %s", result.Outcome)
			}
		})
	}
}

func TestAdapterRejectsUnsafeOrOversizedSummary(t *testing.T) {
	adapter := fixtureAdapter{capabilities: map[Action]bool{Pause: true}, result: Result{Outcome: Acknowledged, Summary: "token=must-not-persist"}}
	if _, err := ApplyConformant(context.Background(), adapter, Request{Action: Pause, TaskID: "T001"}); err == nil {
		t.Fatal("expected unsafe summary rejection")
	}
}
