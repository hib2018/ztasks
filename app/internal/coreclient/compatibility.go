package coreclient

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

const ProductVersion = "0.1.0-dev"
const DataVersion = 1

var ErrIncompatibleCore = errors.New("incompatible ztasks Core; install a matching Frontend/Core archive")

type Compatibility struct {
	ProductVersion  string   `json:"product_version"`
	ProtocolVersion int      `json:"protocol_version"`
	DataVersion     int      `json:"data_version"`
	Capabilities    []string `json:"capabilities"`
}

func VerifyCompatibility(client interface {
	Call(protocol.Request) (protocol.Response, error)
}) error {
	response, err := client.Call(protocol.Request{Version: protocol.Version, RequestID: "compatibility-handshake", Operation: "version.get", Actor: protocol.Actor{Kind: "system", ID: "ztasks-frontend"}, Payload: json.RawMessage(`{}`)})
	if err != nil {
		return fmt.Errorf("compatibility handshake: %w", err)
	}
	if !response.OK {
		return ErrIncompatibleCore
	}
	var report Compatibility
	if json.Unmarshal(response.Result, &report) != nil || report.ProductVersion != ProductVersion || report.ProtocolVersion != protocol.Version || report.DataVersion != DataVersion {
		return ErrIncompatibleCore
	}
	return nil
}
