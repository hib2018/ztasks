package agent

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

type Action string

const (
	Pause   Action = "pause"
	Resume  Action = "resume"
	Retry   Action = "retry"
	Stop    Action = "stop"
	Skip    Action = "skip"
	Inspect Action = "inspect"
)

type Outcome string

const (
	Acknowledged Outcome = "acknowledged"
	Rejected     Outcome = "rejected"
	Unsupported  Outcome = "unsupported"
	Completed    Outcome = "completed"
)

type Capabilities struct {
	Actions map[Action]bool
}

type Request struct {
	Action         Action
	TaskID         string
	RequestEventID string
}

type Result struct {
	Outcome Outcome
	Summary string
}

type Adapter interface {
	Name() string
	Capabilities(context.Context) (Capabilities, error)
	Apply(context.Context, Request) (Result, error)
}

func ApplyConformant(ctx context.Context, adapter Adapter, request Request) (Result, error) {
	capabilities, err := adapter.Capabilities(ctx)
	if err != nil {
		return Result{}, fmt.Errorf("read %s capabilities: %w", adapter.Name(), err)
	}
	if !capabilities.Actions[request.Action] {
		return Result{Outcome: Unsupported}, nil
	}
	result, err := adapter.Apply(ctx, request)
	if err != nil {
		return Result{}, fmt.Errorf("apply %s intervention: %w", adapter.Name(), err)
	}
	if !validOutcome(result.Outcome) {
		return Result{}, fmt.Errorf("adapter returned invalid outcome %q", result.Outcome)
	}
	if err := validateSafeSummary(result.Summary); err != nil {
		return Result{}, err
	}
	return result, nil
}

func validOutcome(outcome Outcome) bool {
	switch outcome {
	case Acknowledged, Rejected, Unsupported, Completed:
		return true
	default:
		return false
	}
}

func validateSafeSummary(summary string) error {
	if len(summary) > 4096 {
		return errors.New("adapter summary exceeds 4096 bytes")
	}
	lower := strings.ToLower(summary)
	for _, marker := range []string{"token=", "secret=", "password=", "api_key=", "authorization:"} {
		if strings.Contains(lower, marker) {
			return errors.New("adapter summary contains secret-like content")
		}
	}
	for _, character := range summary {
		if character < 0x20 && character != '\n' && character != '\t' {
			return errors.New("adapter summary contains control characters")
		}
	}
	return nil
}
