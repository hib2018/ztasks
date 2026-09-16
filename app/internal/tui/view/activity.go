package view

import (
	"fmt"
	"strings"
)

type ActivityEvent struct {
	Sequence  uint64
	Type      string
	TaskID    string
	Timestamp string
	Message   string
}

func RenderActivity(events []ActivityEvent, limit int) string {
	if limit <= 0 || limit > len(events) {
		limit = len(events)
	}
	start := len(events) - limit
	var output strings.Builder
	output.WriteString("Activity\n")
	for _, event := range events[start:] {
		fmt.Fprintf(&output, "%4d %-24s %-7s %s", event.Sequence, event.Type, event.TaskID, event.Timestamp)
		if event.Message != "" {
			fmt.Fprintf(&output, " — %s", event.Message)
		}
		output.WriteByte('\n')
	}
	return output.String()
}
