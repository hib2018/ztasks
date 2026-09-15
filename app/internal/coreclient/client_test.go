package coreclient

import (
	"errors"
	"testing"
)

func TestCommandUsesDirectExecutableAndExplicitArguments(t *testing.T) {
	command := commandFor("/opt/ztasks-core", "/project with spaces", "specs/001/tasks.md")
	if command.Path != "/opt/ztasks-core" {
		t.Fatalf("command path = %q", command.Path)
	}
	want := []string{"/opt/ztasks-core", "serve", "--project-root", "/project with spaces", "--source", "specs/001/tasks.md"}
	if len(command.Args) != len(want) {
		t.Fatalf("args = %#v", command.Args)
	}
	for index := range want {
		if command.Args[index] != want[index] {
			t.Fatalf("arg %d = %q, want %q", index, command.Args[index], want[index])
		}
	}
}

func TestResponseCorrelationRejectsMismatchedIdentity(t *testing.T) {
	line := []byte(`{"version":1,"request_id":"other","ok":true,"result":{},"warnings":[]}`)
	_, err := decodeCorrelatedResponse("req-1", line)
	if !errors.Is(err, ErrMismatchedResponse) {
		t.Fatalf("error = %v, want ErrMismatchedResponse", err)
	}
}

func TestResponseCorrelationAcceptsMatchingIdentity(t *testing.T) {
	line := []byte(`{"version":1,"request_id":"req-1","ok":true,"result":{},"warnings":[]}`)
	response, err := decodeCorrelatedResponse("req-1", line)
	if err != nil {
		t.Fatal(err)
	}
	if !response.OK {
		t.Fatal("expected successful response")
	}
}
