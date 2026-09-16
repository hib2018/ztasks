package view

import (
	"strings"
)

type InterventionView struct {
	Action string
	State  string
	Detail string
}

func RenderInterventions(interventions []InterventionView) string {
	var output strings.Builder
	output.WriteString("Human Intervention\n")
	for _, intervention := range interventions {
		output.WriteString(strings.ToUpper(intervention.Action))
		if intervention.State == "pending" {
			output.WriteString(" REQUESTED")
		} else {
			output.WriteByte(' ')
			output.WriteString(strings.ToUpper(intervention.State))
		}
		if intervention.Detail != "" {
			output.WriteString(" — ")
			output.WriteString(intervention.Detail)
		}
		output.WriteByte('\n')
	}
	return output.String()
}
