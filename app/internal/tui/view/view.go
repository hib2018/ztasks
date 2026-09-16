package view

import (
	"fmt"
	"strings"

	"github.com/hib2018/ztasks/app/internal/tui/model"
)

func Render(state *model.Model) string {
	var output strings.Builder
	width := state.Width()
	if width <= 0 {
		width = 100
	}
	leftWidth := max(28, width*2/5)
	fmt.Fprintf(&output, "%-*s │ %s\n", leftWidth, "Tasks", "Task Detail")
	fmt.Fprintf(&output, "%s─┼─%s\n", strings.Repeat("─", leftWidth), strings.Repeat("─", max(1, width-leftWidth-3)))
	selected := state.Selected()
	visible := state.Visible()
	for index, task := range visible {
		marker := " "
		if task.ID == selected.ID {
			marker = "→"
		}
		left := fmt.Sprintf("%s %-7s %-9s %s", marker, task.ID, strings.ToUpper(task.Status), task.Title)
		right := ""
		if index == 0 && selected.ID != "" {
			right = fmt.Sprintf("%s — %s", selected.ID, selected.Title)
		} else if index == 1 && selected.ID != "" {
			right = "Status: " + strings.ToUpper(selected.Status)
		} else if index == 2 && selected.CurrentAction != "" {
			right = "Current action: " + selected.CurrentAction
		}
		fmt.Fprintf(&output, "%-*.*s │ %s\n", leftWidth, leftWidth, left, right)
	}
	output.WriteString(strings.Repeat("─", leftWidth))
	output.WriteString("─┼─")
	output.WriteString(strings.Repeat("─", max(1, width-leftWidth-3)))
	output.WriteByte('\n')
	fmt.Fprintf(&output, "%-*s │ %s\n", leftWidth, "Activity", "Human Intervention")
	activity := state.Activity()
	interventions := state.Interventions()
	rows := max(len(activity), len(interventions))
	for index := 0; index < rows; index++ {
		left, right := "", ""
		if index < len(activity) {
			left = activity[index].Type + " " + activity[index].TaskID
			if activity[index].Detail != "" {
				left += " — " + activity[index].Detail
			}
		}
		if index < len(interventions) {
			item := interventions[index]
			stateLabel := strings.ToUpper(item.State)
			if item.State == "pending" {
				stateLabel = "REQUESTED"
			}
			right = strings.ToUpper(item.Action) + " " + stateLabel
			if item.Detail != "" {
				right += " — " + item.Detail
			}
		}
		fmt.Fprintf(&output, "%-*.*s │ %s\n", leftWidth, leftWidth, left, right)
	}
	return output.String()
}
