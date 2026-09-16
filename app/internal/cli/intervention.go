package cli

import (
	"encoding/json"
	"errors"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

func BuildInterventionRequest(requestID, command, taskID, message string) (protocol.Request, error) {
	operation, ok := map[string]string{
		"pause": "human.pause_request", "resume": "human.resume_request", "retry": "human.retry_request",
		"stop": "human.stop_request", "skip": "human.skip_request", "inspect": "human.inspect_request", "comment": "human.comment",
	}[command]
	if !ok {
		return protocol.Request{}, errors.New("unknown intervention command")
	}
	payload := map[string]string{}
	if command == "comment" {
		payload["message"] = message
	}
	if command == "inspect" && message != "" {
		payload["focus"] = message
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return protocol.Request{}, err
	}
	return protocol.Request{
		Version: protocol.Version, RequestID: requestID, Operation: operation,
		Actor: protocol.Actor{Kind: "human", ID: "ztasks-cli"}, TaskID: taskID, Payload: encoded,
	}, nil
}

func RenderInterventionAccepted(taskID, action string) string {
	return taskID + " " + action + " requested\n"
}
