package update

import "github.com/hib2018/ztasks/app/internal/tui/model"

type Command int

const (
	MoveUp Command = iota
	MoveDown
	Resize
	Filter
	PageUp
	PageDown
	First
	Last
	FocusNext
	FocusPrevious
	Collapse
	Expand
	TogglePhase
	ToggleAll
)

type Message struct {
	Command       Command
	Width, Height int
	Filter        string
}

func Apply(state *model.Model, message Message) {
	switch message.Command {
	case MoveUp:
		state.Move(-1)
	case MoveDown:
		state.Move(1)
	case Resize:
		state.Resize(message.Width, message.Height)
	case Filter:
		state.Filter(message.Filter)
	case PageUp:
		state.Page(-1)
	case PageDown:
		state.Page(1)
	case First:
		state.Boundary(false)
	case Last:
		state.Boundary(true)
	case FocusNext:
		state.Focus(1)
	case FocusPrevious:
		state.Focus(-1)
	case Collapse:
		expand := false
		state.ToggleSelectedPhase(&expand)
	case Expand:
		expand := true
		state.ToggleSelectedPhase(&expand)
	case TogglePhase:
		state.ToggleSelectedPhase(nil)
	case ToggleAll:
		state.ToggleAllPhases()
	}
}
