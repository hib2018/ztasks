package model

import (
	"os"
	"path/filepath"
	"testing"
)

func TestViewPreferencesRoundTripSelectionAndFilterOnly(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".ztasks", "view.json")
	want := ViewPreferences{Version: 1, SelectedTaskID: "T023", Filter: "running"}
	if err := SaveViewPreferences(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := LoadViewPreferences(path)
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("round trip mismatch: got %#v want %#v", got, want)
	}
	bytes, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"status", "agent", "session_id", "current_action"} {
		if containsJSONKey(bytes, forbidden) {
			t.Fatalf("runtime field %q leaked into view preferences: %s", forbidden, bytes)
		}
	}
}

func TestViewPreferencesMissingFileUsesDefaults(t *testing.T) {
	got, err := LoadViewPreferences(filepath.Join(t.TempDir(), "missing.json"))
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != 1 || got.SelectedTaskID != "" || got.Filter != "" {
		t.Fatalf("unexpected defaults: %#v", got)
	}
}
