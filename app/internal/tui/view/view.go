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

	taskLines := treeLines(state, width-2)
	detailLines := state.DetailLines()
	logLines := state.LogLines()

	taskTitle := "Tasks"
	if summary := statusSummary(state); summary != "" {
		taskTitle += " — " + summary
	}
	var body string
	body = strings.Join(box(taskTitle, taskLines, width, topTotal, state.FocusedPane() == model.TaskPane), "\n") + "\n"
	if width < 64 {
		body += strings.Join(box("State", wrapDetailLines(detailLines, width-2), width, bottomTotal, state.FocusedPane() == model.DetailPane), "\n") + "\n" +
			strings.Join(box("Log", wrapDetailLines(logLines, width-2), width, bottomTotal, state.FocusedPane() == model.ActivityPane), "\n")
	} else {
		left := width / 2
		right := width - left - 1
		body += strings.Join(joinTwoBoxes(
			box("State", wrapDetailLines(detailLines, left-2), left, bottomTotal, state.FocusedPane() == model.DetailPane),
			box("Log", wrapDetailLines(logLines, right-2), right, bottomTotal, state.FocusedPane() == model.ActivityPane),
		), "\n")
	}
	if len(notices) == 0 {
		return body
	}
	return strings.Join(notices, "\n") + "\n" + body
}

func treeLines(state *model.Model, width int) []string {
	selected, hasSelection := state.SelectedTreeRow()
	rows := state.TreeRows()
	chunks := make([][]string, 0, len(rows))
	idWidth, statusWidth := taskColumnWidths(rows)
	selectedIndex := 0
	for index, row := range rows {
		isSelected := hasSelection && row.Kind == selected.Kind && row.Phase == selected.Phase &&
			(row.Kind == model.PhaseRow || row.Task.ID == selected.Task.ID)
		if isSelected {
			selectedIndex = index
		}
		if row.Kind == model.PhaseRow {
			icon, marker := "▶", " "
			if row.Expanded {
				icon = "▼"
			}
			if isSelected {
				marker = "→"
			}
			chunks = append(chunks, []string{marker + " " + icon + " " + displayPhase(row.Phase)})
			continue
		}
		last := index+1 == len(rows) || rows[index+1].Kind != model.TaskRow || rows[index+1].Phase != row.Phase
		branch := "├─ "
		if last {
			branch = "└─ "
		}
		id, status, marker := padCells(row.Task.ID, idWidth), padCells(statusBadge(row.Task.Status), statusWidth), "  "
		if isSelected {
			id, status, marker = selectedText(id), selectedText(status), "→ "
		}
		label := marker + branch + id + " " + status + " "
		branchContinuation := "│  "
		if last {
			branchContinuation = "   "
		}
		indent := strings.Repeat(" ", displayWidth(marker)) + branchContinuation
		wrapped := strings.Split(ansi.Wrap(row.Task.Title, max(1, width-displayWidth(label)), " "), "\n")
		chunk := []string{label + wrapped[0]}
		for _, continuation := range wrapped[1:] {
			chunk = append(chunk, indent+continuation)
		}
		chunks = append(chunks, chunk)
	}
	if len(chunks) == 0 {
		return nil
	}
	viewport := state.Viewport(model.TaskPane)
	start := 0
	for index := 0; index < min(viewport.Offset, len(chunks)); index++ {
		start += len(chunks[index])
	}
	selectedStart := 0
	for index := 0; index < selectedIndex; index++ {
		selectedStart += len(chunks[index])
	}
	selectedEnd := selectedStart + len(chunks[selectedIndex])
	if selectedStart < start {
		start = selectedStart
	}
	if selectedEnd > start+viewport.Height {
		start = max(0, selectedEnd-viewport.Height)
	}
	var lines []string
	for _, chunk := range chunks {
		lines = append(lines, chunk...)
	}
	return lines[min(start, len(lines)):min(len(lines), start+max(1, viewport.Height))]
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

func displayPhase(phase string) string {
	start := strings.Index(phase, " (Priority: ")
	if start < 0 {
		return phase
	}
	close := strings.Index(phase[start:], ")")
	if close < 0 {
		return phase
	}
	priority := phase[start+2 : start+close]
	return phase[:start] + "  " + priority + phase[start+close+1:]
}

func taskColumnWidths(rows []model.TreeRow) (int, int) {
	idWidth, statusWidth := 0, 0
	for _, row := range rows {
		if row.Kind != model.TaskRow {
			continue
		}
		idWidth = max(idWidth, displayWidth(row.Task.ID))
		statusWidth = max(statusWidth, displayWidth(statusBadge(row.Task.Status)))
	}
	return idWidth, statusWidth
}

func padCells(value string, width int) string {
	return value + strings.Repeat(" ", max(0, width-displayWidth(value)))
}

func statusSummary(state *model.Model) string {
	counts := map[string]int{}
	for _, task := range state.Tasks() {
		counts[strings.ToLower(task.Status)]++
	}
	order := []string{"running", "blocked", "failed", "paused", "ready", "pending", "completed", "skipped"}
	parts := make([]string, 0, len(counts))
	for _, status := range order {
		if counts[status] != 0 {
			parts = append(parts, fmt.Sprintf("%s:%d", statusLabel(status), counts[status]))
			delete(counts, status)
		}
	}
	for status, count := range counts {
		parts = append(parts, fmt.Sprintf("%s:%d", strings.ToUpper(status), count))
	}
	return strings.Join(parts, "  ")
}

func statusBadge(status string) string { return "[" + statusLabel(status) + "]" }

func statusLabel(status string) string {
	switch strings.ToLower(status) {
	case "ready":
		return "READY"
	case "pending":
		return "PENDING"
	case "running":
		return "RUNNING"
	case "paused":
		return "PAUSED"
	case "blocked":
		return "BLOCKED"
	case "failed":
		return "FAILED"
	case "completed":
		return "DONE"
	case "skipped":
		return "SKIPPED"
	default:
		return strings.ToUpper(status)
	}
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
func joinTwoBoxes(left, right []string) []string {
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
