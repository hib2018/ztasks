package update

import "github.com/hib2018/ztasks/app/internal/tui/model"

type Command int

const (
	MoveUp Command = iota
	MoveDown
	Resize
	Filter
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
	}
}
