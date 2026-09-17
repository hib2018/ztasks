package e2e_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestRecognizedSecretsAreAbsentAndProhibitedFieldsNeverEcho(t *testing.T) {
	root := repositoryRoot(t)
	build(t, root)
	project := executionProject(t)
	secret := "ghp_fixture_secret_123456"
	accepted := `{"version":1,"request_id":"safe-comment","op":"human.comment","actor":{"kind":"human","id":"operator"},"task_id":"T001","payload":{"message":"credential ` + secret + `"}}`
	prohibitedValue := "private-thought-fixture"
	rejected := `{"version":1,"request_id":"reject-private","op":"human.comment","actor":{"kind":"human","id":"operator"},"task_id":"T001","payload":{"private_reasoning":"` + prohibitedValue + `"}}`
	responses := runCoreLines(t, root, project, accepted, rejected)
	joined := bytes.Join(responses, nil)
	if bytes.Contains(joined, []byte(secret)) || bytes.Contains(joined, []byte(prohibitedValue)) {
		t.Fatalf("response echoed protected bytes: %s", joined)
	}
	if !bytes.Contains(joined, []byte("[REDACTED:provider-token]")) || !bytes.Contains(joined, []byte("prohibited_field")) {
		t.Fatalf("expected policy outcomes missing: %s", joined)
	}
	events, err := os.ReadFile(filepath.Join(project, ".ztasks", "events.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(events, []byte(secret)) || bytes.Contains(events, []byte(prohibitedValue)) {
		t.Fatal("protected bytes reached durable history")
	}
}
