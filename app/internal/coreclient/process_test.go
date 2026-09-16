package coreclient

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

func TestProcessRejectsMalformedAndWrongIdentityResponses(t *testing.T) {
	for _, mode := range []string{"malformed", "wrong-id"} {
		t.Run(mode, func(t *testing.T) {
			client := startHelper(t, mode)
			defer client.Close()
			_, err := client.CallContext(context.Background(), testRequest("req-1"))
			if err == nil {
				t.Fatal("expected response rejection")
			}
		})
	}
}

func TestProcessDrainsStderrWithoutBlockingStdout(t *testing.T) {
	client := startHelper(t, "stderr-flood")
	defer client.Close()
	response, err := client.CallContext(context.Background(), testRequest("req-1"))
	if err != nil {
		t.Fatal(err)
	}
	if !response.OK {
		t.Fatal("expected successful response")
	}
}

func TestTimeoutCanRetrySameRequestIdentity(t *testing.T) {
	client := startHelper(t, "timeout-once")
	defer client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	request := testRequest("req-retry")
	if _, err := client.CallContext(ctx, request); err == nil {
		t.Fatal("expected timeout")
	}
	response, err := client.CallContext(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	if response.RequestID != request.RequestID {
		t.Fatal("retry changed request identity")
	}
}

func startHelper(t *testing.T, mode string) *Client {
	t.Helper()
	command := exec.Command(os.Args[0], "-test.run=TestCoreClientHelper", "--", mode)
	command.Env = append(os.Environ(), "ZTASKS_CORECLIENT_HELPER=1")
	client, err := startProcess(command)
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func testRequest(id string) protocol.Request {
	return protocol.Request{Version: 1, RequestID: id, Operation: "version.get", Actor: protocol.Actor{Kind: "human"}, Payload: json.RawMessage(`{}`)}
}

func TestCoreClientHelper(t *testing.T) {
	if os.Getenv("ZTASKS_CORECLIENT_HELPER") != "1" {
		return
	}
	mode := os.Args[len(os.Args)-1]
	decoder := json.NewDecoder(os.Stdin)
	encoder := json.NewEncoder(os.Stdout)
	count := 0
	for {
		var request protocol.Request
		if err := decoder.Decode(&request); err != nil {
			os.Exit(0)
		}
		count++
		switch mode {
		case "malformed":
			fmt.Fprintln(os.Stdout, "not-json")
		case "wrong-id":
			_ = encoder.Encode(map[string]any{"version": 1, "request_id": "wrong", "ok": true, "result": map[string]any{}, "warnings": []any{}})
		case "stderr-flood":
			fmt.Fprint(os.Stderr, strings.Repeat("diagnostic\n", 200000))
			_ = encoder.Encode(map[string]any{"version": 1, "request_id": request.RequestID, "ok": true, "result": map[string]any{}, "warnings": []any{}})
		case "timeout-once":
			if count == 1 {
				time.Sleep(60 * time.Millisecond)
			}
			_ = encoder.Encode(map[string]any{"version": 1, "request_id": request.RequestID, "ok": true, "result": map[string]any{}, "warnings": []any{}})
		}
	}
}
