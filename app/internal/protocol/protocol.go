package protocol

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
)

const (
	Version     = 1
	MaxLineSize = 1_048_576
)

var (
	ErrInvalidEnvelope    = errors.New("invalid protocol envelope")
	ErrLineTooLarge       = errors.New("protocol line exceeds 1 MiB")
	ErrUnsupportedVersion = errors.New("unsupported protocol version")
)

type Actor struct {
	Kind string `json:"kind"`
	ID   string `json:"id,omitempty"`
}

type Request struct {
	Version   int             `json:"version"`
	RequestID string          `json:"request_id"`
	Operation string          `json:"op"`
	Actor     Actor           `json:"actor"`
	TaskID    string          `json:"task_id,omitempty"`
	Payload   json.RawMessage `json:"payload"`
}

type ProtocolError struct {
	Code    string          `json:"code"`
	Message string          `json:"message"`
	Details json.RawMessage `json:"details"`
}

type Response struct {
	Version   int               `json:"version"`
	RequestID string            `json:"request_id"`
	OK        bool              `json:"ok"`
	Result    json.RawMessage   `json:"result,omitempty"`
	Error     *ProtocolError    `json:"error,omitempty"`
	Warnings  []json.RawMessage `json:"warnings,omitempty"`
}

type Envelope struct {
	Request  *Request
	Response *Response
}

func DecodeLine(line []byte) (Envelope, error) {
	if len(line) > MaxLineSize {
		return Envelope{}, ErrLineTooLarge
	}

	var discriminator map[string]json.RawMessage
	if err := json.Unmarshal(line, &discriminator); err != nil {
		return Envelope{}, fmt.Errorf("%w: malformed JSON", ErrInvalidEnvelope)
	}
	if _, isRequest := discriminator["op"]; isRequest {
		var request Request
		if err := decodeStrict(line, &request); err != nil {
			return Envelope{}, err
		}
		if err := validateVersionAndIdentity(request.Version, request.RequestID); err != nil {
			return Envelope{}, err
		}
		if request.Operation == "" || request.Actor.Kind == "" || len(request.Payload) == 0 {
			return Envelope{}, ErrInvalidEnvelope
		}
		return Envelope{Request: &request}, nil
	}
	if _, isResponse := discriminator["ok"]; isResponse {
		var response Response
		if err := decodeStrict(line, &response); err != nil {
			return Envelope{}, err
		}
		if err := validateVersionAndIdentity(response.Version, response.RequestID); err != nil {
			return Envelope{}, err
		}
		if response.OK && len(response.Result) == 0 {
			return Envelope{}, ErrInvalidEnvelope
		}
		if !response.OK && response.Error == nil {
			return Envelope{}, ErrInvalidEnvelope
		}
		return Envelope{Response: &response}, nil
	}
	return Envelope{}, ErrInvalidEnvelope
}

func decodeStrict(line []byte, destination any) error {
	decoder := json.NewDecoder(bytes.NewReader(line))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return fmt.Errorf("%w: %v", ErrInvalidEnvelope, err)
	}
	if decoder.More() {
		return ErrInvalidEnvelope
	}
	return nil
}

func validateVersionAndIdentity(version int, requestID string) error {
	if version != Version {
		return ErrUnsupportedVersion
	}
	if requestID == "" {
		return ErrInvalidEnvelope
	}
	return nil
}
