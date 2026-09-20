package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/hib2018/ztasks/app/internal/coreclient"
	"github.com/hib2018/ztasks/app/internal/protocol"
)

const Version = "0.1.0-dev"

const Help = `ztasks - Agent Task Execution human control surface

Usage:
  ztasks [tui]
  ztasks init [tasks.md]
  ztasks bootstrap --from-checkboxes [tasks.md]
  ztasks sync [tasks.md]
  ztasks status [--json]
  ztasks task show <id> [--json]
  ztasks doctor [--json]
  ztasks help
  ztasks version
`

func VersionReport() string {
	frontend := "ztasks " + Version
	executable, err := os.Executable()
	if err != nil {
		return frontend + "\nCore: unavailable; reinstall the matching ztasks archive"
	}
	core, err := coreclient.DiscoverCore(executable, os.Getenv("ZTASKS_CORE"))
	if err != nil {
		return frontend + "\nCore: unavailable; reinstall the matching ztasks archive"
	}
	return frontend + "\nCore: " + core
}

func BuildProjectRequest(requestID, command, locator string) protocol.Request {
	operation := map[string]string{"init": "project.init", "bootstrap": "project.bootstrap", "sync": "source.sync", "inspect": "project.inspect", "doctor": "health.check"}[command]
	payload := map[string]string{}
	if command == "bootstrap" {
		payload["mode"] = "speckit_checkboxes"
	}
	if locator != "" {
		payload["locator"] = locator
	}
	encoded, _ := json.Marshal(payload)
	return protocol.Request{Version: protocol.Version, RequestID: requestID, Operation: operation, Actor: protocol.Actor{Kind: "human", ID: "ztasks-cli"}, Payload: encoded}
}

func RenderProjectResult(command string, result json.RawMessage, machineReadable bool) (string, error) {
	if machineReadable {
		if !json.Valid(result) {
			return "", errors.New("core returned invalid JSON")
		}
		return string(result) + "\n", nil
	}
	if command == "doctor" {
		var report struct {
			Healthy     bool `json:"healthy"`
			Diagnostics []struct {
				Code     string `json:"code"`
				Severity string `json:"severity"`
				Message  string `json:"message"`
			} `json:"diagnostics"`
		}
		if err := json.Unmarshal(result, &report); err != nil {
			return "", err
		}
		var output strings.Builder
		for _, diagnostic := range report.Diagnostics {
			fmt.Fprintf(&output, "%s: %s\n", diagnostic.Code, diagnostic.Message)
		}
		return output.String(), nil
	}
	var value struct {
		Event struct {
			Type string `json:"type"`
		} `json:"event"`
	}
	if err := json.Unmarshal(result, &value); err != nil {
		return "", err
	}
	return value.Event.Type + "\n", nil
}
