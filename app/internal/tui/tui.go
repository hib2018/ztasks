package tui

import (
	tea "charm.land/bubbletea/v2"

	"github.com/hib2018/ztasks/app/internal/tui/model"
	modelupdate "github.com/hib2018/ztasks/app/internal/tui/update"
	modelview "github.com/hib2018/ztasks/app/internal/tui/view"
)

type Monitor struct {
	state     *model.Model
	filtering bool
	filter    string
}

func New(tasks []model.Task) *Monitor {
	return &Monitor{state: model.New(tasks)}
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
		case "/":
			monitor.filtering = true
		}
	}
	return monitor, nil
}

func (monitor *Monitor) View() tea.View {
	content := modelview.Render(monitor.state)
	if monitor.filtering || monitor.filter != "" {
		content += "\nFilter: " + monitor.filter
	}
	content += "\n↑/k ↓/j select  / filter  q quit"
	return tea.NewView(content)
}
