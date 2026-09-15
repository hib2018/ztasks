package contract_test

import (
	"bufio"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
)

func TestZigAndGoAcceptSharedEnvelopeFixtures(t *testing.T) {
	root := repositoryRoot(t)
	fixture := filepath.Join(root, "protocol", "fixtures", "v1", "envelopes.jsonl")
	assertJSONLines(t, fixture, 6)

	run(t, root, []string{
		"ZIG_GLOBAL_CACHE_DIR=" + filepath.Join(root, ".zig-global-cache"),
	}, "zig", "build", "--build-file", "core/build.zig", "--cache-dir", ".zig-cache", "test")
	run(t, filepath.Join(root, "app"), []string{
		"GOCACHE=" + filepath.Join(root, ".go-build-cache"),
	}, "go", "test", "./internal/protocol")
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot resolve contract test location")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(filename), "..", ".."))
}

func assertJSONLines(t *testing.T, path string, expected int) {
	t.Helper()
	file, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()

	count := 0
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		count++
		var value any
		if err := json.Unmarshal(scanner.Bytes(), &value); err != nil {
			t.Fatalf("fixture line %d is invalid JSON: %v", count, err)
		}
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if count != expected {
		t.Fatalf("fixture count = %d, want %d", count, expected)
	}
}

func run(t *testing.T, directory string, environment []string, name string, arguments ...string) {
	t.Helper()
	command := exec.Command(name, arguments...)
	command.Dir = directory
	command.Env = append(os.Environ(), environment...)
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("%s failed: %v\n%s", name, err, output)
	}
}
