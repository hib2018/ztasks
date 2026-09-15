package protocol

import (
	"bufio"
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestGoldenEnvelopesDecode(t *testing.T) {
	fixture := filepath.Join("..", "..", "..", "protocol", "fixtures", "v1", "envelopes.jsonl")
	file, err := os.Open(fixture)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	line := 0
	for scanner.Scan() {
		line++
		if _, err := DecodeLine(scanner.Bytes()); err != nil {
			t.Fatalf("fixture line %d: %v", line, err)
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if line == 0 {
		t.Fatal("fixture contains no envelopes")
	}
}

func TestUnknownEnvelopeFieldRejected(t *testing.T) {
	line := []byte(`{"version":1,"request_id":"req-1","ok":true,"result":{},"warnings":[],"extra":true}`)
	if _, err := DecodeLine(line); err == nil {
		t.Fatal("expected unknown field rejection")
	}
}

func TestResponseIdentityIsRequired(t *testing.T) {
	line := bytes.Clone([]byte(`{"version":1,"ok":true,"result":{},"warnings":[]}`))
	if _, err := DecodeLine(line); err == nil {
		t.Fatal("expected missing request_id rejection")
	}
}
