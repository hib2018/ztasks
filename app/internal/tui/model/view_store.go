package model

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

type ViewPreferences struct {
	Version        int    `json:"version"`
	SelectedTaskID string `json:"selected_task_id,omitempty"`
	Filter         string `json:"filter,omitempty"`
}

func LoadViewPreferences(path string) (ViewPreferences, error) {
	document, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return ViewPreferences{Version: 1}, nil
	}
	if err != nil {
		return ViewPreferences{}, fmt.Errorf("read view preferences: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(document))
	decoder.DisallowUnknownFields()
	var preferences ViewPreferences
	if err := decoder.Decode(&preferences); err != nil || preferences.Version != 1 {
		return ViewPreferences{}, fmt.Errorf("decode view preferences: invalid version or JSON")
	}
	return preferences, nil
}

func SaveViewPreferences(path string, preferences ViewPreferences) error {
	preferences.Version = 1
	encoded, err := json.Marshal(preferences)
	if err != nil {
		return fmt.Errorf("encode view preferences: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create view preferences directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".view-*.tmp")
	if err != nil {
		return fmt.Errorf("create temporary view preferences: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err = temporary.Write(append(encoded, '\n')); err == nil {
		err = temporary.Sync()
	}
	if closeErr := temporary.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return fmt.Errorf("write view preferences: %w", err)
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("replace view preferences: %w", err)
	}
	return nil
}

func containsJSONKey(document []byte, key string) bool {
	var values map[string]json.RawMessage
	if json.Unmarshal(document, &values) != nil {
		return false
	}
	_, found := values[key]
	return found
}
