package view

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/x/ansi"
	"github.com/hib2018/ztasks/app/internal/tui/model"
)

func Render(state *model.Model) string {
	var notices []string
	project := state.ProjectStatus()
	if project.DefinitionMissing {
		notices = append(notices, "DEFINITION MISSING — run ztasks sync after restoring tasks.md")
	}
	if len(project.SyncAdded)+len(project.SyncChanged)+len(project.SyncMissing)+len(project.SyncReappeared) > 0 {
		notices = append(notices, fmt.Sprintf("Sync: +%s ~%s -%s ↻%s", strings.Join(project.SyncAdded, ","), strings.Join(project.SyncChanged, ","), strings.Join(project.SyncMissing, ","), strings.Join(project.SyncReappeared, ",")))
	}
	for _, warning := range project.Warnings {
		notices = append(notices, "Warning: "+warning)
	}

	width := state.Width()
	if width <= 0 {
		width = 100
	}
	height := state.Height()
	if height <= 0 {
		height = 30
	}
	usable := max(10, height-len(notices)-2)
	topTotal := max(5, usable/2)
	bottomTotal := max(4, usable-topTotal)
	state.SetViewportHeights(topTotal-2, bottomTotal-2)

	taskWidth := width - 2
	if width >= 64 {
		taskWidth = max(8, width*2/5-2)
	}
	taskLines := treeLines(state, taskWidth)
	detailLines := state.DetailLines()
	activityLines := activityLines(state)
	interventionLines := interventionLines(state)

	var body string
	if width < 64 {
		body = strings.Join(box("Tasks", taskLines, width, topTotal, state.FocusedPane() == model.TaskPane), "\n") + "\n" +
			strings.Join(box("Task Detail", wrapDetailLines(detailLines, width-2), width, topTotal, state.FocusedPane() == model.DetailPane), "\n") + "\n" +
			strings.Join(box("Activity", activityLines, width, bottomTotal, state.FocusedPane() == model.ActivityPane), "\n") + "\n" +
			strings.Join(box("Human Intervention", interventionLines, width, bottomTotal, state.FocusedPane() == model.InterventionPane), "\n")
	} else {
		left := max(28, width*2/5)
		right := max(28, width-left-1)
		body = strings.Join(joinBoxes(box("Tasks", taskLines, left, topTotal, state.FocusedPane() == model.TaskPane), box("Task Detail", wrapDetailLines(detailLines, right-2), right, topTotal, state.FocusedPane() == model.DetailPane)), "\n") + "\n" +
			strings.Join(joinBoxes(box("Activity", activityLines, left, bottomTotal, state.FocusedPane() == model.ActivityPane), box("Human Intervention", interventionLines, right, bottomTotal, state.FocusedPane() == model.InterventionPane)), "\n")
	}
	if len(notices) == 0 {
		return body
	}
	return strings.Join(notices, "\n") + "\n" + body
}

func treeLines(state *model.Model, width int) []string {
	selected, hasSelection := state.SelectedTreeRow()
	rows := state.VisibleTreeRows()
	lines := make([]string, 0, len(rows))
	for _, row := range rows {
		if row.Kind == model.PhaseRow {
			icon := "▶"
			if row.Expanded {
				icon = "▼"
			}
			marker := " "
			if hasSelection && selected.Kind == model.PhaseRow && selected.Phase == row.Phase {
				marker = "→"
			}
			lines = append(lines, marker+" "+icon+" "+row.Phase)
			continue
		}
		last := true
		for index, candidate := range rows {
			if candidate.Kind != model.TaskRow || candidate.Task.ID != row.Task.ID {
				continue
			}
			for _, next := range rows[index+1:] {
				if next.Kind == model.TaskRow && next.Phase == row.Phase {
					last = false
				}
				break
			}
			break
		}
		branch := "├─ "
		if last {
			branch = "└─ "
		}
		id, status, marker := row.Task.ID, "["+strings.ToUpper(row.Task.Status)+"]", "  "
		if hasSelection && selected.Kind == model.TaskRow && row.Task.ID == selected.Task.ID {
			id, status, marker = selectedText(id), selectedText(status), "→ "
		}
		label := marker + branch + id + " " + status + " "
		indent := strings.Repeat(" ", displayWidth(label))
		wrapped := strings.Split(ansi.Wrap(row.Task.Title, max(1, width-displayWidth(label)), " "), "\n")
		lines = append(lines, label+wrapped[0])
		for _, continuation := range wrapped[1:] {
			lines = append(lines, indent+continuation)
		}
	}
	return lines
}
func activityLines(state *model.Model) []string {
	all := state.Activity()
	v := state.Viewport(model.ActivityPane)
	a := clamp(v.Offset, 0, len(all))
	b := min(len(all), a+max(1, v.Height))
	out := make([]string, 0, b-a)
	for _, item := range all[a:b] {
		line := item.Type + " " + item.TaskID
		if item.Stale {
			line = "[STALE] " + line
		}
		if item.Detail != "" {
			line += " — " + item.Detail
		}
		out = append(out, line)
	}
	return out
}
func interventionLines(state *model.Model) []string {
	all := state.Interventions()
	v := state.Viewport(model.InterventionPane)
	a := clamp(v.Offset, 0, len(all))
	b := min(len(all), a+max(1, v.Height))
	out := make([]string, 0, b-a)
	for _, item := range all[a:b] {
		label := strings.ToUpper(item.State)
		if item.State == "pending" {
			label = "REQUESTED"
		}
		line := strings.ToUpper(item.Action) + " " + label
		if item.Detail != "" {
			line += " — " + item.Detail
		}
		out = append(out, line)
	}
	return out
}

func wrapDetailLines(lines []string, width int) []string {
	if width <= 0 {
		return nil
	}
	wrapped := make([]string, 0, len(lines))
	for _, line := range lines {
		indent := leadingSpaces(line)
		content := strings.TrimPrefix(line, indent)
		contentWidth := width - displayWidth(indent)
		if contentWidth <= 0 {
			wrapped = append(wrapped, fit(indent, width))
			continue
		}
		parts := strings.Split(ansi.Wrap(content, contentWidth, " "), "\n")
		for _, part := range parts {
			wrapped = append(wrapped, indent+part)
		}
	}
	return wrapped
}

func selectedText(value string) string {
	return "\x1b[38;5;230;48;5;62m" + value + "\x1b[0m"
}

func leadingSpaces(value string) string {
	return value[:len(value)-len(strings.TrimLeft(value, " "))]
}

func box(title string, content []string, width, height int, focused bool) []string {
	width = max(4, width)
	height = max(3, height)
	inner := width - 2
	label := " " + title + " "
	if focused {
		label = "[ " + title + " ]"
	}
	label = fit(label, max(0, inner))
	top := "┌" + label + strings.Repeat("─", max(0, inner-displayWidth(label))) + "┐"
	lines := []string{top}
	for i := 0; i < height-2; i++ {
		text := ""
		if i < len(content) {
			text = content[i]
		}
		text = fit(text, inner)
		lines = append(lines, "│"+text+strings.Repeat(" ", max(0, inner-displayWidth(text)))+"│")
	}
	lines = append(lines, "└"+strings.Repeat("─", inner)+"┘")
	return lines
}
func joinBoxes(left, right []string) []string {
	n := min(len(left), len(right))
	out := make([]string, n)
	for i := 0; i < n; i++ {
		out[i] = left[i] + " " + right[i]
	}
	return out
}
func fit(value string, limit int) string {
	if limit <= 0 {
		return ""
	}
	return ansi.Truncate(value, limit, "")
}
func displayWidth(value string) int { return ansi.StringWidth(value) }
func clamp(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
