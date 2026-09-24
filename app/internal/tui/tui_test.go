package tui

import (
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/hib2018/ztasks/app/internal/tui/model"
)

func TestMonitorUsesAlternateScreen(t *testing.T) {
	view := New(nil).View()
	if !view.AltScreen {
		t.Fatal("monitor must render in the alternate screen buffer")
	}
}

func TestBootstrapKeyRefreshesTasks(t *testing.T) {
	monitor := NewWithBootstrap([]model.Task{{ID: "T001", Status: "ready"}}, func() ([]model.Task, error) {
		return []model.Task{{ID: "T001", Status: "completed"}}, nil
	})
	_, _ = monitor.Update(tea.KeyPressMsg(tea.Key{Text: "b", Code: 'b'}))
	view := monitor.View().Content
	if !strings.Contains(view, "[DONE]") || !strings.Contains(view, "Bootstrap complete") {
		t.Fatalf("bootstrap did not refresh view: %q", view)
	}
}
