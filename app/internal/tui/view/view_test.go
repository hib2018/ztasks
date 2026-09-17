package view

import (
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/hib2018/ztasks/app/internal/tui/model"
)

func TestRenderHandlesNarrowResizeUnicodeAndKeyboardSelectionState(t *testing.T) {
	state := model.New([]model.Task{{ID: "T001", Title: "日本語の長い作業名", Status: "ready"}, {ID: "T002", Title: "next", Status: "pending"}})
	state.Resize(18, 5)
	state.Move(1)
	output := Render(state)
	if !utf8.ValidString(output) {
		t.Fatalf("render split UTF-8: %q", output)
	}
	if !strings.Contains(output, "T002") {
		t.Fatalf("keyboard selection missing: %q", output)
	}
	state.Resize(120, 40)
	if state.Selected().ID != "T002" {
		t.Fatal("resize lost selection")
	}
}
