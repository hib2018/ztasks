package view

import (
	"strings"
	"testing"

	"github.com/hib2018/ztasks/app/internal/tui/model"
)

func TestRenderShowsMissingDefinitionSyncWarningsAndStaleActivity(t *testing.T) {
	state := model.New([]model.Task{{ID: "T001", Title: "Work", Status: "missing"}})
	state.SetProjectStatus(model.ProjectStatus{
		DefinitionMissing: true,
		SyncAdded:         []string{"T002"},
		SyncMissing:       []string{"T001"},
		Warnings:          []string{"snapshot is stale"},
	})
	state.SetActivity([]model.Activity{{Type: "task.progress", TaskID: "T001", Detail: "old action", Stale: true}})
	output := Render(state)
	for _, expected := range []string{"DEFINITION MISSING", "Sync: +T002", "-T001", "Warning: snapshot is stale", "[STALE]"} {
		if !strings.Contains(output, expected) {
			t.Fatalf("render omitted %q: %s", expected, output)
		}
	}
}
