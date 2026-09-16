package model

import "strings"

type Task struct {
	ID                      string
	Phase                   string
	Title                   string
	Status                  string
	Agent                   string
	SessionID               string
	CurrentAction           string
	UnsatisfiedDependencies []string
}

type Activity struct {
	Type   string
	TaskID string
	Detail string
}

type Intervention struct {
	Action string
	State  string
	Detail string
}

type Model struct {
	tasks         []Task
	visible       []int
	selected      int
	selectedID    string
	filter        string
	activity      []Activity
	interventions []Intervention
	width, height int
}

func New(tasks []Task) *Model {
	state := &Model{tasks: append([]Task(nil), tasks...)}
	state.rebuildVisible()
	return state
}

func (state *Model) Move(delta int) {
	if len(state.visible) == 0 {
		return
	}
	state.selected += delta
	if state.selected < 0 {
		state.selected = 0
	}
	if state.selected >= len(state.visible) {
		state.selected = len(state.visible) - 1
	}
	state.selectedID = state.Selected().ID
}

func (state *Model) Filter(query string) {
	state.filter = strings.TrimSpace(strings.ToLower(query))
	state.rebuildVisible()
}

func (state *Model) Resize(width, height int) {
	state.width = max(0, width)
	state.height = max(0, height)
}

func (state *Model) Width() int  { return state.width }
func (state *Model) Height() int { return state.height }

func (state *Model) Selected() Task {
	if len(state.visible) == 0 {
		return Task{}
	}
	return state.tasks[state.visible[state.selected]]
}

func (state *Model) Detail() Task { return state.Selected() }

func (state *Model) SetActivity(activity []Activity) {
	state.activity = append([]Activity(nil), activity...)
}

func (state *Model) Activity() []Activity {
	return append([]Activity(nil), state.activity...)
}

func (state *Model) SetInterventions(interventions []Intervention) {
	state.interventions = append([]Intervention(nil), interventions...)
}

func (state *Model) Interventions() []Intervention {
	return append([]Intervention(nil), state.interventions...)
}

func (state *Model) Visible() []Task {
	visible := make([]Task, 0, len(state.visible))
	for _, index := range state.visible {
		visible = append(visible, state.tasks[index])
	}
	return visible
}

func (state *Model) rebuildVisible() {
	state.visible = state.visible[:0]
	for index, task := range state.tasks {
		searchable := strings.ToLower(task.ID + " " + task.Phase + " " + task.Title + " " + task.Status)
		if state.filter == "" || strings.Contains(searchable, state.filter) {
			state.visible = append(state.visible, index)
		}
	}
	state.selected = 0
	if state.selectedID != "" {
		for index, taskIndex := range state.visible {
			if state.tasks[taskIndex].ID == state.selectedID {
				state.selected = index
				break
			}
		}
	}
	if len(state.visible) != 0 {
		state.selectedID = state.Selected().ID
	}
}
