package model

import "testing"

func TestSelectionFilteringAndDetail(t *testing.T) {
	state := New([]Task{
		{ID: "T001", Phase: "Setup", Title: "Build core", Status: "completed"},
		{ID: "T002", Phase: "Parser", Title: "Add parser", Status: "running"},
	})
	if state.Selected().ID != "T001" {
		t.Fatalf("initial selection = %q", state.Selected().ID)
	}
	state.Move(1)
	if state.Selected().ID != "T002" || state.Detail().Title != "Add parser" {
		t.Fatalf("selection/detail did not move together: %#v", state.Detail())
	}
	state.Filter("setup")
	if state.Selected().ID != "T001" || len(state.Visible()) != 1 {
		t.Fatalf("filter did not retain phase match: %#v", state.Visible())
	}
}

func TestResizeRetainsSelection(t *testing.T) {
	state := New([]Task{{ID: "T001"}, {ID: "T002"}})
	state.Move(1)
	state.Resize(120, 40)
	if state.Width() != 120 || state.Height() != 40 || state.Selected().ID != "T002" {
		t.Fatal("resize changed selection or lost dimensions")
	}
}
