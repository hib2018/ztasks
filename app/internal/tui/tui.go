package tui

import (
	tea "charm.land/bubbletea/v2"

	"github.com/hib2018/ztasks/app/internal/tui/model"
	modelupdate "github.com/hib2018/ztasks/app/internal/tui/update"
	modelview "github.com/hib2018/ztasks/app/internal/tui/view"
)

type BootstrapFunc func() ([]model.Task, error)

type Monitor struct {
	state     *model.Model
	filtering bool
	filter    string
	bootstrap BootstrapFunc
	notice    string
}

func New(tasks []model.Task) *Monitor {
	return NewWithBootstrap(tasks, nil)
}

func NewWithBootstrap(tasks []model.Task, bootstrap BootstrapFunc) *Monitor {
	return &Monitor{state: model.New(tasks), bootstrap: bootstrap}
}

func (monitor *Monitor) Init() tea.Cmd { return nil }

func (monitor *Monitor) Update(message tea.Msg) (tea.Model, tea.Cmd) {
	switch message := message.(type) {
	case tea.WindowSizeMsg:
		modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.Resize, Width: message.Width, Height: message.Height})
	case tea.KeyPressMsg:
		key := message.String()
		if monitor.filtering {
			switch key {
			case "enter", "esc":
				monitor.filtering = false
			case "backspace":
				if len(monitor.filter) != 0 {
					monitor.filter = monitor.filter[:len(monitor.filter)-1]
				}
			default:
				if len(key) == 1 {
					monitor.filter += key
				}
			}
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.Filter, Filter: monitor.filter})
			return monitor, nil
		}
		switch key {
		case "q", "ctrl+c":
			return monitor, tea.Quit
		case "up", "k":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.MoveUp})
		case "down", "j":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.MoveDown})
		case "pgup", "ctrl+u":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.PageUp})
		case "pgdown", "ctrl+d":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.PageDown})
		case "home", "g":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.First})
		case "end", "G":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.Last})
		case "tab":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.FocusNext})
		case "shift+tab":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.FocusPrevious})
		case "left", "h":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.Collapse})
		case "right", "l":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.Expand})
		case "space", "o":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.TogglePhase})
		case "z":
			modelupdate.Apply(monitor.state, modelupdate.Message{Command: modelupdate.ToggleAll})
		case "b":
			if monitor.bootstrap != nil {
				tasks, err := monitor.bootstrap()
				if err != nil {
					monitor.notice = "Bootstrap failed: " + err.Error()
				} else {
					monitor.state.SetTasks(tasks)
					monitor.notice = "Bootstrap complete"
				}
			}
		case "/":
			monitor.filtering = true
		}
	}
	return monitor, nil
}

func (monitor *Monitor) View() tea.View {
	content := modelview.Render(monitor.state)
	if monitor.notice != "" {
		content += "\n" + monitor.notice
	}
	if monitor.filtering || monitor.filter != "" {
		content += "\nFilter: " + monitor.filter
	}
	content += "\nTab pane  ↑/k ↓/j scroll  PgUp/PgDn page  h/l fold  space/o toggle  b bootstrap  / filter  q quit"
	view := tea.NewView(content)
	view.AltScreen = true
	return view
}
