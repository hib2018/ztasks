package coreclient

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

type compatibilityCaller struct{ result json.RawMessage }

func (caller compatibilityCaller) Call(request protocol.Request) (protocol.Response, error) {
	return protocol.Response{Version: 1, RequestID: request.RequestID, OK: true, Result: caller.result}, nil
}

func TestCompatibilityRefusesEveryMismatchWithUpdateGuidance(t *testing.T) {
	valid := `{"product_version":"0.1.0-dev","protocol_version":1,"data_version":1,"capabilities":[]}`
	if err := VerifyCompatibility(compatibilityCaller{json.RawMessage(valid)}); err != nil {
		t.Fatal(err)
	}
	for _, invalid := range []string{
		`{"product_version":"0.2.0","protocol_version":1,"data_version":1}`,
		`{"product_version":"0.1.0-dev","protocol_version":2,"data_version":1}`,
		`{"product_version":"0.1.0-dev","protocol_version":1,"data_version":2}`,
	} {
		if err := VerifyCompatibility(compatibilityCaller{json.RawMessage(invalid)}); !errors.Is(err, ErrIncompatibleCore) {
			t.Fatalf("mismatch error = %v", err)
		}
	}
}
