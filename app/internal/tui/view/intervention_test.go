package view

import (
	"strings"
	"testing"
)

func TestInterventionViewSeparatesPendingAndConfirmedLifecycle(t *testing.T) {
	pending := RenderInterventions([]InterventionView{{Action: "pause", State: "pending"}})
	if !strings.Contains(pending, "PAUSE REQUESTED") || strings.Contains(pending, "PAUSED") {
		t.Fatalf("pending request looks confirmed: %q", pending)
	}
	confirmed := RenderInterventions([]InterventionView{{Action: "pause", State: "resolved"}})
	if !strings.Contains(confirmed, "PAUSE RESOLVED") {
		t.Fatalf("resolved request not visible: %q", confirmed)
	}
}
