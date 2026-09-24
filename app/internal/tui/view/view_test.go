package view

import (
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/charmbracelet/x/ansi"
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

func TestRenderFramesEveryPaneAndMarksFocus(t *testing.T) {
	state := model.New([]model.Task{{ID: "T001", Phase: "Setup", Title: "Work", Status: "ready"}})
	state.Resize(100, 24)
	state.SetActivity([]model.Activity{{Type: "task.started", TaskID: "T001"}})
	state.SetInterventions([]model.Intervention{{Action: "pause", State: "pending"}})
	output := Render(state)
	for _, title := range []string{"[ Tasks — READY:1 ]", "Task Detail", "Activity", "Human Intervention"} {
		if !strings.Contains(output, title) {
			t.Fatalf("framed pane %q missing: %s", title, output)
		}
	}
	if strings.Count(output, "┌") < 4 || strings.Count(output, "┘") < 4 {
		t.Fatalf("not every pane is framed: %s", output)
	}
}

func TestTreeMarksSelectedPhaseRow(t *testing.T) {
	state := model.New([]model.Task{{ID: "T001", Phase: "Setup", Title: "Work", Status: "ready"}})
	state.Move(-1)
	state.Resize(80, 20)
	if output := Render(state); !strings.Contains(output, "→ ▼ Setup") {
		t.Fatalf("selected phase marker missing: %s", output)
	}
}

func TestTaskTreeSelectionWrappingAndPaneHeights(t *testing.T) {
	state := model.New([]model.Task{
		{ID: "T001", Phase: "Setup", Title: "A deliberately long task name that wraps", Status: "ready"},
		{ID: "T002", Phase: "Setup", Title: "Next", Status: "pending"},
	})
	state.Resize(48, 30)
	state.Move(1)
	output := Render(state)
	if !strings.Contains(output, selectedText("T002")) || !strings.Contains(output, selectedText("[PENDING]")) {
		t.Fatalf("selected task number/status not highlighted: %q", output)
	}
	if strings.Count(output, "→") != 1 || !strings.Contains(output, "├─") || !strings.Contains(output, "└─") {
		t.Fatalf("task tree or unique selection marker missing: %s", output)
	}
	lines := strings.Split(output, "\n")
	for index, line := range lines {
		if strings.Contains(line, "deliberately long") {
			if index+1 >= len(lines) || !strings.HasPrefix(lines[index+1], "│  │") {
				t.Fatalf("wrapped title continuation is not aligned with tree guide: %q", lines[index+1])
			}
			break
		}
	}
	if state.Viewport(model.TaskPane).Height >= state.Height()/2 {
		t.Fatalf("task pane should use the upper half: %#v", state.Viewport(model.TaskPane))
	}
}

func TestDuplicateTaskIDsShowOneSelectionArrow(t *testing.T) {
	state := model.New([]model.Task{
		{ID: "T001", Phase: "specs/001/tasks.md", Title: "First", Status: "ready"},
		{ID: "T001", Phase: "specs/002/tasks.md", Title: "Second", Status: "pending"},
	})
	state.Resize(100, 24)
	state.Boundary(true)
	output := Render(state)
	if strings.Count(output, "→") != 1 || !strings.Contains(output, selectedText("[PENDING]")) {
		t.Fatalf("duplicate IDs produced ambiguous selection: %s", output)
	}
}

func TestRenderKeepsFrameWidthWithWideCharacters(t *testing.T) {
	state := model.New([]model.Task{{ID: "T001", Phase: "日本語フェーズ", Title: "日本語の長い作業名", Status: "ready"}})
	state.Resize(80, 24)
	state.SetActivity([]model.Activity{{Type: "task.progress", TaskID: "T001", Detail: "実装しています🚀"}})
	state.SetInterventions([]model.Intervention{{Action: "comment", State: "pending", Detail: "人間の確認待ち"}})

	for number, line := range strings.Split(Render(state), "\n") {
		if got := ansi.StringWidth(line); got != 80 {
			t.Fatalf("line %d display width = %d, want 80: %q", number+1, got, line)
		}
	}
}

func TestFitUsesTerminalCellWidth(t *testing.T) {
	got := fit("日本語abc", 7)
	if width := ansi.StringWidth(got); width > 7 {
		t.Fatalf("fit width = %d, want <= 7: %q", width, got)
	}
	if got != "日本語a" {
		t.Fatalf("fit = %q, want %q", got, "日本語a")
	}
}

func TestWrapDetailLinesPreservesItemIndent(t *testing.T) {
	lines := wrapDetailLines([]string{
		"Current action: 日本語を含む長い処理内容を確認しています",
		"  ○ T001-日本語の長い依存タスク名 (unsatisfied)",
	}, 20)
	if len(lines) < 4 {
		t.Fatalf("detail items were not wrapped: %#v", lines)
	}
	for number, line := range lines {
		if width := ansi.StringWidth(line); width > 20 {
			t.Fatalf("line %d width = %d, want <= 20: %q", number+1, width, line)
		}
	}
	if strings.HasPrefix(lines[0], " ") || strings.HasPrefix(lines[1], " ") {
		t.Fatalf("unindented item continuation shifted: %#v", lines[:2])
	}
	dependencyStart := -1
	for index, line := range lines {
		if strings.Contains(line, "T001") {
			dependencyStart = index
			break
		}
	}
	if dependencyStart < 0 || dependencyStart+1 >= len(lines) {
		t.Fatalf("wrapped dependency missing: %#v", lines)
	}
	for _, line := range lines[dependencyStart:] {
		if !strings.HasPrefix(line, "  ") {
			t.Fatalf("dependency continuation lost indent: %q", line)
		}
	}
}
