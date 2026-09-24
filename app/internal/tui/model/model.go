package model

import "strings"

type Task struct {
	ID, Phase, Title, Status, Agent, SessionID, CurrentAction, Source string
	UnsatisfiedDependencies                                           []string
}
type Activity struct {
	Type, TaskID, Detail string
	Stale                bool
}
type ProjectStatus struct {
	DefinitionMissing                                             bool
	SyncAdded, SyncChanged, SyncMissing, SyncReappeared, Warnings []string
}
type Intervention struct{ Action, State, Detail string }

type Pane int

const (
	TaskPane Pane = iota
	DetailPane
	ActivityPane
	InterventionPane
)

type RowKind int

const (
	PhaseRow RowKind = iota
	TaskRow
)

type TreeRow struct {
	Kind     RowKind
	Phase    string
	Task     Task
	Expanded bool
}
type Viewport struct{ Offset, Height int }

type Model struct {
	tasks                             []Task
	visible                           []int
	selected                          int
	selectedID, selectedPhase, filter string
	activity                          []Activity
	interventions                     []Intervention
	project                           ProjectStatus
	collapsed                         map[string]bool
	treeCursor                        int
	focused                           Pane
	viewports                         [4]Viewport
	width, height                     int
}

func New(tasks []Task) *Model {
	s := &Model{tasks: append([]Task(nil), tasks...), collapsed: map[string]bool{}}
	s.rebuildVisible()
	return s
}
func (s *Model) Width() int      { return s.width }
func (s *Model) Height() int     { return s.height }
func (s *Model) Resize(w, h int) { s.width = max(0, w); s.height = max(0, h) }
func (s *Model) Selected() Task {
	if row, ok := s.SelectedTreeRow(); ok {
		if row.Kind == TaskRow {
			return row.Task
		}
		for _, task := range s.tasks {
			if task.Phase == row.Phase && s.matches(task) {
				return task
			}
		}
	}
	if len(s.visible) == 0 {
		return Task{}
	}
	return s.tasks[s.visible[s.selected]]
}
func (s *Model) SelectedTreeRow() (TreeRow, bool) {
	rows := s.TreeRows()
	if len(rows) == 0 {
		return TreeRow{}, false
	}
	s.treeCursor = clamp(s.treeCursor, 0, len(rows)-1)
	return rows[s.treeCursor], true
}
func (s *Model) Detail() Task             { return s.Selected() }
func (s *Model) FilterValue() string      { return s.filter }
func (s *Model) FocusedPane() Pane        { return s.focused }
func (s *Model) Viewport(p Pane) Viewport { return s.viewports[p] }
func (s *Model) SetActivity(v []Activity) { s.activity = append([]Activity(nil), v...) }
func (s *Model) Activity() []Activity     { return append([]Activity(nil), s.activity...) }
func (s *Model) SetInterventions(v []Intervention) {
	s.interventions = append([]Intervention(nil), v...)
}
func (s *Model) Interventions() []Intervention {
	return append([]Intervention(nil), s.interventions...)
}
func (s *Model) SetProjectStatus(v ProjectStatus) { s.project = v }
func (s *Model) ProjectStatus() ProjectStatus     { return s.project }

func (s *Model) Move(delta int) {
	if s.focused != TaskPane {
		s.scroll(s.focused, delta)
		return
	}
	rows := s.TreeRows()
	if len(rows) == 0 {
		return
	}
	s.selectTreeRow(clamp(s.treeCursor+delta, 0, len(rows)-1))
}
func (s *Model) Page(delta int) {
	h := max(1, s.viewports[s.focused].Height)
	if s.focused == TaskPane {
		s.Move(delta * max(1, h-1))
	} else {
		s.scroll(s.focused, delta*h)
	}
}
func (s *Model) Boundary(last bool) {
	if s.focused == TaskPane {
		rows := s.TreeRows()
		if len(rows) == 0 {
			return
		}
		if last {
			s.selectTreeRow(len(rows) - 1)
		} else {
			s.selectTreeRow(0)
		}
		return
	}
	if last {
		s.viewports[s.focused].Offset = max(0, s.paneLength(s.focused)-s.viewports[s.focused].Height)
	} else {
		s.viewports[s.focused].Offset = 0
	}
}
func (s *Model) Focus(delta int) {
	n := int(ActivityPane) + 1
	s.focused = Pane((int(s.focused) + delta + n) % n)
}
func (s *Model) Filter(q string) {
	s.filter = strings.TrimSpace(strings.ToLower(q))
	s.rebuildVisible()
}
func (s *Model) ToggleSelectedPhase(expand *bool) {
	row, ok := s.SelectedTreeRow()
	if !ok {
		return
	}
	p := row.Phase
	if p == "" {
		return
	}
	if expand == nil {
		s.collapsed[p] = !s.collapsed[p]
	} else {
		s.collapsed[p] = !*expand
	}
	s.rebuildVisible()
	for index, candidate := range s.TreeRows() {
		if candidate.Kind == PhaseRow && candidate.Phase == p {
			s.treeCursor = index
			break
		}
	}
	s.ensureCursorVisible()
}
func (s *Model) ToggleAllPhases() {
	all := true
	for _, t := range s.tasks {
		if !s.collapsed[t.Phase] {
			all = false
			break
		}
	}
	for _, t := range s.tasks {
		s.collapsed[t.Phase] = !all
	}
	s.rebuildVisible()
}
func (s *Model) SetViewportHeights(top, bottom int) {
	s.viewports[TaskPane].Height = max(1, top)
	s.viewports[DetailPane].Height = max(1, bottom)
	s.viewports[ActivityPane].Height = max(1, bottom)
	s.ensureCursorVisible()
	for p := DetailPane; p <= ActivityPane; p++ {
		s.viewports[p].Offset = clamp(s.viewports[p].Offset, 0, max(0, s.paneLength(p)-s.viewports[p].Height))
	}
}

func (s *Model) Tasks() []Task { return append([]Task(nil), s.tasks...) }

func (s *Model) Visible() []Task {
	out := make([]Task, 0, len(s.visible))
	for _, i := range s.visible {
		out = append(out, s.tasks[i])
	}
	return out
}
func (s *Model) TreeRows() []TreeRow {
	rows := make([]TreeRow, 0, len(s.visible)+8)
	seen := map[string]bool{}
	for _, t := range s.tasks {
		if !s.matches(t) {
			continue
		}
		if !seen[t.Phase] {
			seen[t.Phase] = true
			rows = append(rows, TreeRow{Kind: PhaseRow, Phase: t.Phase, Expanded: s.filter != "" || !s.collapsed[t.Phase]})
		}
		if s.filter != "" || !s.collapsed[t.Phase] {
			rows = append(rows, TreeRow{Kind: TaskRow, Phase: t.Phase, Task: t})
		}
	}
	return rows
}
func (s *Model) VisibleTreeRows() []TreeRow {
	rows := s.TreeRows()
	v := s.viewports[TaskPane]
	a := clamp(v.Offset, 0, len(rows))
	b := min(len(rows), a+max(1, v.Height))
	return append([]TreeRow(nil), rows[a:b]...)
}
func (s *Model) DetailLines() []string {
	lines := s.detailLines()
	v := s.viewports[DetailPane]
	a := clamp(v.Offset, 0, len(lines))
	b := min(len(lines), a+max(1, v.Height))
	return append([]string(nil), lines[a:b]...)
}
func (s *Model) LogLines() []string {
	lines := s.logLines()
	v := s.viewports[ActivityPane]
	a := clamp(v.Offset, 0, len(lines))
	b := min(len(lines), a+max(1, v.Height))
	return append([]string(nil), lines[a:b]...)
}

func (s *Model) rebuildVisible() {
	s.visible = s.visible[:0]
	for i, t := range s.tasks {
		if s.matches(t) && (s.filter != "" || !s.collapsed[t.Phase]) {
			s.visible = append(s.visible, i)
		}
	}
	s.selected = 0
	if s.selectedID != "" {
		for n, i := range s.visible {
			if sameTask(s.tasks[i], s.selectedPhase, s.selectedID) {
				s.selected = n
				break
			}
		}
	}
	if len(s.visible) > 0 {
		selected := s.tasks[s.visible[s.selected]]
		s.selectedID, s.selectedPhase = selected.ID, selected.Phase
	}
	rows := s.TreeRows()
	for index, row := range rows {
		if row.Kind == TaskRow && sameTask(row.Task, s.selectedPhase, s.selectedID) {
			s.treeCursor = index
			break
		}
	}
	s.ensureCursorVisible()
}
func (s *Model) matches(t Task) bool {
	return s.filter == "" || strings.Contains(strings.ToLower(t.ID+" "+t.Phase+" "+t.Title+" "+t.Status), s.filter)
}
func (s *Model) ensureCursorVisible() {
	rows := s.TreeRows()
	if len(rows) == 0 {
		s.treeCursor = 0
		s.viewports[TaskPane].Offset = 0
		return
	}
	s.treeCursor = clamp(s.treeCursor, 0, len(rows)-1)
	v := &s.viewports[TaskPane]
	if s.treeCursor < v.Offset {
		v.Offset = s.treeCursor
	}
	if v.Height > 0 && s.treeCursor >= v.Offset+v.Height {
		v.Offset = s.treeCursor - v.Height + 1
	}
	v.Offset = clamp(v.Offset, 0, max(0, len(rows)-max(1, v.Height)))
}
func (s *Model) selectTreeRow(index int) {
	rows := s.TreeRows()
	if len(rows) == 0 {
		return
	}
	s.treeCursor = clamp(index, 0, len(rows)-1)
	row := rows[s.treeCursor]
	selected := Task{}
	if row.Kind == TaskRow {
		selected = row.Task
	} else {
		for _, task := range s.tasks {
			if task.Phase == row.Phase && s.matches(task) {
				selected = task
				break
			}
		}
	}
	if selected.ID != "" {
		s.selectedID, s.selectedPhase = selected.ID, selected.Phase
		for visibleIndex, taskIndex := range s.visible {
			if sameTask(s.tasks[taskIndex], selected.Phase, selected.ID) {
				s.selected = visibleIndex
				break
			}
		}
	}
	s.ensureCursorVisible()
}
func sameTask(task Task, phase, id string) bool { return task.ID == id && task.Phase == phase }

func (s *Model) scroll(p Pane, d int) {
	v := &s.viewports[p]
	v.Offset = clamp(v.Offset+d, 0, max(0, s.paneLength(p)-max(1, v.Height)))
}
func (s *Model) paneLength(p Pane) int {
	switch p {
	case DetailPane:
		return len(s.detailLines())
	case ActivityPane:
		return len(s.logLines())
	default:
		return len(s.TreeRows())
	}
}
func (s *Model) detailLines() []string {
	t := s.Selected()
	if t.ID == "" {
		return nil
	}
	out := []string{t.ID + " — " + t.Title, "Status: " + strings.ToUpper(t.Status), "Phase: " + t.Phase}
	if t.Agent != "" {
		out = append(out, "Agent: "+t.Agent)
	}
	if t.SessionID != "" {
		out = append(out, "Session: "+t.SessionID)
	}
	if t.CurrentAction != "" {
		out = append(out, "Current action: "+t.CurrentAction)
	}
	if len(t.UnsatisfiedDependencies) > 0 {
		out = append(out, "Dependencies:")
		for _, d := range t.UnsatisfiedDependencies {
			out = append(out, "  ○ "+d+" (unsatisfied)")
		}
	}
	if len(s.interventions) > 0 {
		out = append(out, "Human requests:")
		for _, item := range s.interventions {
			line := "  " + strings.ToUpper(item.Action) + " " + strings.ToUpper(item.State)
			if item.State == "pending" {
				line = "  " + strings.ToUpper(item.Action) + " REQUESTED"
			}
			if item.Detail != "" {
				line += " — " + item.Detail
			}
			out = append(out, line)
		}
	}
	return out
}
func (s *Model) logLines() []string {
	out := make([]string, 0, len(s.activity)+len(s.interventions))
	for _, item := range s.activity {
		line := item.Type + " " + item.TaskID
		if item.Stale {
			line = "[STALE] " + line
		}
		if item.Detail != "" {
			line += " — " + item.Detail
		}
		out = append(out, line)
	}
	for _, item := range s.interventions {
		label := strings.ToUpper(item.State)
		if item.State == "pending" {
			label = "REQUESTED"
		}
		line := "human." + item.Action + " " + label
		if item.Detail != "" {
			line += " — " + item.Detail
		}
		out = append(out, line)
	}
	return out
}
func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
