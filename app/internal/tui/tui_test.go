package tui

import "testing"

func TestMonitorUsesAlternateScreen(t *testing.T) {
	view := New(nil).View()
	if !view.AltScreen {
		t.Fatal("monitor must render in the alternate screen buffer")
	}
}
