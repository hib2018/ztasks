package model

import (
	"strings"
	"testing"
)

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

func TestDetailShowsOnlyRuntimeState(t *testing.T) {
	state := New([]Task{{
		ID: "T001", Phase: "Setup", Title: "Build core", Status: "running",
		Agent: "pi", SessionID: "session-1", CurrentAction: "editing",
		UnsatisfiedDependencies: []string{"T000"},
	}})
	state.SetInterventions([]Intervention{{Action: "pause", State: "pending"}})
	state.SetViewportHeights(20, 20)
	lines := state.DetailLines()
	joined := strings.Join(lines, "\n")
	for _, expected := range []string{"Agent", "Session", "Current action", "Unsatisfied dependencies", "Human requests"} {
		if !strings.Contains(joined, expected) {
			t.Fatalf("runtime state omitted %q: %s", expected, joined)
		}
	}
	for _, duplicate := range []string{"Task", "Title", "Status", "Phase"} {
		if strings.Contains(joined, duplicate+" ") {
			t.Fatalf("state duplicated task field %q: %s", duplicate, joined)
		}
	}
}

func TestDetailShowsEmptyRuntimeState(t *testing.T) {
	state := New([]Task{{ID: "T001", Phase: "Setup", Title: "Build core", Status: "ready"}})
	if got := state.DetailLines(); len(got) != 1 || got[0] != "No active runtime state" {
		t.Fatalf("empty runtime state = %#v", got)
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

func TestTaskViewportFollowsSelectionAndPages(t *testing.T) {
	tasks := make([]Task, 12)
	for index := range tasks {
		tasks[index] = Task{ID: "T" + string(rune('A'+index)), Phase: "Phase", Status: "ready"}
	}
	state := New(tasks)
	state.SetViewportHeights(4, 3)
	state.Page(1)
	if state.Selected().ID != "TD" {
		t.Fatalf("page selection = %q", state.Selected().ID)
	}
	viewport := state.Viewport(TaskPane)
	if viewport.Offset == 0 {
		t.Fatal("selection did not scroll task viewport")
	}
	state.Boundary(true)
	if state.Selected().ID != "TL" {
		t.Fatalf("end selection = %q", state.Selected().ID)
	}
}

func TestDuplicateTaskIDsKeepSourceSelectionAndScrollPosition(t *testing.T) {
	state := New([]Task{
		{ID: "T001", Phase: "specs/001/tasks.md", Title: "First"},
		{ID: "T001", Phase: "specs/002/tasks.md", Title: "Second"},
	})
	state.SetViewportHeights(2, 2)
	state.Boundary(true)
	if selected := state.Selected(); selected.Title != "Second" {
		t.Fatalf("selected duplicate task = %#v", selected)
	}
	if offset := state.Viewport(TaskPane).Offset; offset != 2 {
		t.Fatalf("task viewport offset = %d, want 2", offset)
	}
}

func TestPhaseTreeCollapsesAndCanReopen(t *testing.T) {
	state := New([]Task{{ID: "T001", Phase: "Setup"}, {ID: "T002", Phase: "Setup"}, {ID: "T003", Phase: "Runtime"}})
	if len(state.TreeRows()) != 5 {
		t.Fatalf("expanded rows = %d", len(state.TreeRows()))
	}
	expand := false
	state.ToggleSelectedPhase(&expand)
	if rows := state.TreeRows(); len(rows) != 3 || rows[0].Kind != PhaseRow || rows[0].Expanded {
		t.Fatalf("collapsed tree = %#v", rows)
	}
	expand = true
	state.ToggleSelectedPhase(&expand)
	if len(state.TreeRows()) != 5 {
		t.Fatal("collapsed phase could not be reopened")
	}
}

func TestPhaseRowsAreSelectableAndControlTheirOwnFold(t *testing.T) {
	state := New([]Task{{ID: "T001", Phase: "Setup"}, {ID: "T002", Phase: "Setup"}, {ID: "T003", Phase: "Runtime"}})
	state.Move(-1)
	selected, ok := state.SelectedTreeRow()
	if !ok || selected.Kind != PhaseRow || selected.Phase != "Setup" {
		t.Fatalf("selected row = %#v, %v", selected, ok)
	}

	state.ToggleSelectedPhase(nil)
	selected, ok = state.SelectedTreeRow()
	if !ok || selected.Kind != PhaseRow || selected.Phase != "Setup" || selected.Expanded {
		t.Fatalf("collapsed phase selection = %#v, %v", selected, ok)
	}
	if rows := state.TreeRows(); len(rows) != 3 {
		t.Fatalf("collapsed rows = %d, want 3", len(rows))
	}

	state.ToggleSelectedPhase(nil)
	selected, _ = state.SelectedTreeRow()
	if !selected.Expanded || len(state.TreeRows()) != 5 {
		t.Fatalf("reopened phase = %#v", selected)
	}
}
