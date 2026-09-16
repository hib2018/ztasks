package cli

import (
	"encoding/json"
	"errors"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

var ErrEventTypeNotAllowed = errors.New("event type is not allowed for event emit")

func BuildExecutionRequest(requestID, command, taskID, message, agent, session string) (protocol.Request, error) {
	operation, ok := map[string]string{
		"start": "task.start", "block": "task.block", "fail": "task.fail", "complete": "task.complete",
	}[command]
	if !ok {
		return protocol.Request{}, errors.New("unknown execution command")
	}
	payload := map[string]string{}
	switch command {
	case "start":
		if session != "" {
			payload["session_id"] = session
		}
	case "block":
		payload["reason"] = message
	case "fail":
		payload["code"] = "execution_failed"
		payload["message"] = message
	case "complete":
		if message != "" {
			payload["result"] = message
		}
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return protocol.Request{}, err
	}
	actorID := agent
	if actorID == "" {
		actorID = "ztasks-cli"
	}
	return protocol.Request{
		Version: protocol.Version, RequestID: requestID, Operation: operation,
		Actor: protocol.Actor{Kind: "human", ID: actorID}, TaskID: taskID, Payload: encoded,
	}, nil
}

func BuildEventListRequest(requestID, taskID string) protocol.Request {
	return protocol.Request{
		Version: protocol.Version, RequestID: requestID, Operation: "event.list",
		Actor: protocol.Actor{Kind: "human", ID: "ztasks-cli"}, TaskID: taskID, Payload: json.RawMessage(`{}`),
	}
}

func EventEmitOperation(eventType string) (string, error) {
	operations := map[string]string{
		"task.progress": "task.progress", "task.paused": "task.pause_ack", "task.resumed": "task.resume_ack",
		"task.blocked": "task.block", "task.failed": "task.fail", "task.completed": "task.complete",
		"task.skipped": "task.skip", "task.comment": "task.comment", "intervention.responded": "intervention.respond",
	}
	operation, ok := operations[eventType]
	if !ok {
		return "", ErrEventTypeNotAllowed
	}
	return operation, nil
}

func BuildEventEmitRequest(requestID, eventType, taskID string, payload json.RawMessage) (protocol.Request, error) {
	operation, err := EventEmitOperation(eventType)
	if err != nil {
		return protocol.Request{}, err
	}
	return protocol.Request{
		Version: protocol.Version, RequestID: requestID, Operation: operation,
		Actor: protocol.Actor{Kind: "adapter", ID: "ztasks-event-emit"}, TaskID: taskID, Payload: payload,
	}, nil
}

func EventEmitPayload(eventType, message string) (json.RawMessage, error) {
	payload := map[string]string{}
	switch eventType {
	case "task.progress":
		payload["current_action"] = message
	case "task.blocked":
		payload["reason"] = message
	case "task.failed":
		payload["code"] = "execution_failed"
		payload["message"] = message
	case "task.completed":
		if message != "" {
			payload["result"] = message
		}
	case "task.comment":
		payload["message"] = message
	case "task.paused", "task.resumed", "task.skipped":
	case "intervention.responded":
		payload["outcome"] = message
	default:
		return nil, ErrEventTypeNotAllowed
	}
	return json.Marshal(payload)
}

func Execute(client caller, request protocol.Request) (json.RawMessage, error) {
	response, err := client.Call(request)
	if err != nil {
		return nil, err
	}
	if !response.OK {
		return nil, responseError(response)
	}
	return response.Result, nil
}

func RenderExecutionResult(result json.RawMessage, machineReadable bool) (string, error) {
	if machineReadable {
		var compact json.RawMessage
		if err := json.Unmarshal(result, &compact); err != nil {
			return "", err
		}
		return string(result) + "\n", nil
	}
	var value struct {
		Event struct {
			Type   string `json:"type"`
			TaskID string `json:"task_id"`
		} `json:"event"`
		Runtime struct {
			Status string `json:"status"`
		} `json:"runtime"`
	}
	if err := json.Unmarshal(result, &value); err != nil {
		return "", err
	}
	return value.Event.TaskID + " " + value.Event.Type + " (" + value.Runtime.Status + ")\n", nil
}
