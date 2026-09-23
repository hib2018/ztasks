package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

type TaskView struct {
	Source                  string   `json:"source,omitempty"`
	ID                      string   `json:"id"`
	Phase                   string   `json:"phase"`
	Title                   string   `json:"title"`
	Status                  string   `json:"status"`
	Agent                   string   `json:"agent,omitempty"`
	SessionID               string   `json:"session_id,omitempty"`
	CurrentAction           string   `json:"current_action,omitempty"`
	UnsatisfiedDependencies []string `json:"unsatisfied_dependencies,omitempty"`
}

type StatusSource struct {
	Path   string     `json:"path"`
	Digest string     `json:"digest"`
	Tasks  []TaskView `json:"tasks"`
}

type StatusView struct {
	Tasks   []TaskView     `json:"tasks"`
	Sources []StatusSource `json:"sources,omitempty"`
}

type caller interface {
	Call(protocol.Request) (protocol.Response, error)
}

func FetchStatus(client caller, requestID string) (StatusView, error) {
	response, err := client.Call(readRequest(requestID, "task.list", ""))
	if err != nil {
		return StatusView{}, err
	}
	if !response.OK {
		return StatusView{}, responseError(response)
	}
	var status StatusView
	if err := decodeResult(response.Result, &status); err != nil {
		return StatusView{}, err
	}
	return status, nil
}

func FetchTask(client caller, requestID, taskID string) (TaskView, error) {
	response, err := client.Call(readRequest(requestID, "task.show", taskID))
	if err != nil {
		return TaskView{}, err
	}
	if !response.OK {
		return TaskView{}, responseError(response)
	}
	var wrapper struct {
		Task TaskView `json:"task"`
	}
	if err := decodeResult(response.Result, &wrapper); err != nil {
		return TaskView{}, err
	}
	return wrapper.Task, nil
}

func RenderStatus(status StatusView, machineReadable bool) (string, error) {
	if machineReadable {
		return renderJSON(status)
	}
	var output strings.Builder
	if len(status.Sources) != 0 {
		for _, source := range status.Sources {
			fmt.Fprintf(&output, "%s  sha256:%s  (%d tasks)\n", source.Path, source.Digest, len(source.Tasks))
			for _, task := range source.Tasks {
				fmt.Fprintf(&output, "  ├─ %-8s %-10s %s", task.ID, strings.ToUpper(task.Status), task.Title)
				if len(task.UnsatisfiedDependencies) != 0 {
					fmt.Fprintf(&output, " (depends on %s)", strings.Join(task.UnsatisfiedDependencies, ", "))
				}
				output.WriteByte('\n')
			}
		}
		return output.String(), nil
	}
	var phase string
	for _, task := range status.Tasks {
		if task.Phase != phase {
			if output.Len() != 0 {
				output.WriteByte('\n')
			}
			phase = task.Phase
			fmt.Fprintln(&output, phase)
		}
		fmt.Fprintf(&output, "  %-8s %-10s %s", task.ID, strings.ToUpper(task.Status), task.Title)
		if len(task.UnsatisfiedDependencies) != 0 {
			fmt.Fprintf(&output, " (%s unsatisfied)", strings.Join(task.UnsatisfiedDependencies, ", "))
		}
		output.WriteByte('\n')
	}
	return output.String(), nil
}

func RenderTask(task TaskView, machineReadable bool) (string, error) {
	if machineReadable {
		return renderJSON(task)
	}
	var output strings.Builder
	fmt.Fprintf(&output, "%s — %s\n", task.ID, task.Title)
	fmt.Fprintf(&output, "Phase: %s\nStatus: %s\n", task.Phase, task.Status)
	if task.Agent != "" {
		fmt.Fprintf(&output, "Agent: %s\n", task.Agent)
	}
	if task.SessionID != "" {
		fmt.Fprintf(&output, "Session: %s\n", task.SessionID)
	}
	if task.CurrentAction != "" {
		fmt.Fprintf(&output, "Current action: %s\n", task.CurrentAction)
	}
	if len(task.UnsatisfiedDependencies) != 0 {
		fmt.Fprintf(&output, "Unsatisfied dependencies: %s\n", strings.Join(task.UnsatisfiedDependencies, ", "))
	}
	return output.String(), nil
}

func readRequest(requestID, operation, taskID string) protocol.Request {
	return protocol.Request{
		Version:   protocol.Version,
		RequestID: requestID,
		Operation: operation,
		Actor:     protocol.Actor{Kind: "human", ID: "ztasks-cli"},
		TaskID:    taskID,
		Payload:   json.RawMessage(`{}`),
	}
}

func decodeResult(raw json.RawMessage, destination any) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return fmt.Errorf("decode core result: %w", err)
	}
	return nil
}

func responseError(response protocol.Response) error {
	if response.Error == nil {
		return fmt.Errorf("core rejected request without an error")
	}
	return fmt.Errorf("%s: %s", response.Error.Code, response.Error.Message)
}

func renderJSON(value any) (string, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	return string(encoded) + "\n", nil
}
