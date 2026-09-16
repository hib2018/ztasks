package cli

import (
	tea "charm.land/bubbletea/v2"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/hib2018/ztasks/app/internal/coreclient"
	"github.com/hib2018/ztasks/app/internal/protocol"
	"github.com/hib2018/ztasks/app/internal/tui"
	tuimodel "github.com/hib2018/ztasks/app/internal/tui/model"
)

func Run(arguments []string, stdout, stderr io.Writer) int {
	if len(arguments) == 0 {
		arguments = []string{"tui"}
	}
	machineReadable := false
	filtered := make([]string, 0, len(arguments))
	for _, argument := range arguments {
		if argument == "--json" {
			machineReadable = true
			continue
		}
		filtered = append(filtered, argument)
	}
	if len(filtered) == 0 {
		fmt.Fprintln(stderr, "missing command")
		return 2
	}

	projectRoot, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(stderr, "cannot determine project root")
		return 3
	}
	client, err := coreclient.Start(coreExecutable(projectRoot), projectRoot, "")
	if err != nil {
		fmt.Fprintln(stderr, "cannot start ztasks core")
		return 3
	}
	defer client.Close()

	requestID := newRequestID()
	var output string
	switch {
	case len(filtered) == 1 && filtered[0] == "tui":
		status, fetchErr := FetchStatus(client, requestID)
		if fetchErr != nil {
			err = fetchErr
			break
		}
		tasks := make([]tuimodel.Task, len(status.Tasks))
		for index, task := range status.Tasks {
			tasks[index] = tuimodel.Task{
				ID: task.ID, Phase: task.Phase, Title: task.Title, Status: task.Status,
				Agent: task.Agent, SessionID: task.SessionID, CurrentAction: task.CurrentAction,
				UnsatisfiedDependencies: task.UnsatisfiedDependencies,
			}
		}
		_, err = tea.NewProgram(tui.New(tasks), tea.WithInput(os.Stdin), tea.WithOutput(stdout)).Run()
		if err == nil {
			return 0
		}
	case len(filtered) == 1 && filtered[0] == "status":
		view, fetchErr := FetchStatus(client, requestID)
		if fetchErr == nil {
			output, fetchErr = RenderStatus(view, machineReadable)
		}
		err = fetchErr
	case len(filtered) == 3 && filtered[0] == "task" && filtered[1] == "show":
		view, fetchErr := FetchTask(client, requestID, filtered[2])
		if fetchErr == nil {
			output, fetchErr = RenderTask(view, machineReadable)
		}
		err = fetchErr
	case len(filtered) >= 2 && (filtered[0] == "start" || filtered[0] == "block" || filtered[0] == "fail" || filtered[0] == "complete"):
		message := ""
		if len(filtered) > 2 {
			message = strings.Join(filtered[2:], " ")
		}
		request, buildErr := BuildExecutionRequest(requestID, filtered[0], filtered[1], message, "", "")
		if buildErr == nil {
			var result []byte
			result, buildErr = Execute(client, request)
			if buildErr == nil {
				output, buildErr = RenderExecutionResult(result, machineReadable)
			}
		}
		err = buildErr
	case len(filtered) >= 2 && (filtered[0] == "pause" || filtered[0] == "resume" || filtered[0] == "retry" || filtered[0] == "stop" || filtered[0] == "skip" || filtered[0] == "inspect" || filtered[0] == "comment"):
		message := ""
		if len(filtered) > 2 {
			message = strings.Join(filtered[2:], " ")
		}
		request, buildErr := BuildInterventionRequest(requestID, filtered[0], filtered[1], message)
		if buildErr == nil {
			var result []byte
			result, buildErr = Execute(client, request)
			if buildErr == nil {
				if machineReadable {
					output = string(result) + "\n"
				} else {
					output = RenderInterventionAccepted(filtered[1], filtered[0])
				}
			}
		}
		err = buildErr
	case len(filtered) >= 2 && filtered[0] == "event" && filtered[1] == "list":
		taskID := ""
		if len(filtered) == 3 {
			taskID = filtered[2]
		}
		result, fetchErr := Execute(client, BuildEventListRequest(requestID, taskID))
		if fetchErr == nil {
			if machineReadable {
				output = string(result) + "\n"
			} else {
				output = string(result) + "\n"
			}
		}
		err = fetchErr
	case len(filtered) >= 6 && filtered[0] == "event" && filtered[1] == "emit":
		values := flagValues(filtered[2:])
		eventType, hasType := values["--type"]
		taskID, hasTask := values["--task"]
		if !hasType || !hasTask {
			err = fmt.Errorf("event emit requires --type and --task")
			break
		}
		payload, buildErr := EventEmitPayload(eventType, values["--message"])
		if buildErr == nil {
			var request protocol.Request
			request, buildErr = BuildEventEmitRequest(requestID, eventType, taskID, payload)
			if buildErr == nil {
				var result []byte
				result, buildErr = Execute(client, request)
				if buildErr == nil {
					output, buildErr = RenderExecutionResult(result, machineReadable)
				}
			}
		}
		err = buildErr
	default:
		fmt.Fprintln(stderr, "unsupported command")
		return 2
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 4
	}
	if _, err := io.WriteString(stdout, output); err != nil {
		return 3
	}
	return 0
}

func flagValues(arguments []string) map[string]string {
	values := make(map[string]string)
	for index := 0; index+1 < len(arguments); index += 2 {
		values[arguments[index]] = arguments[index+1]
	}
	return values
}

func coreExecutable(projectRoot string) string {
	if configured := os.Getenv("ZTASKS_CORE"); configured != "" {
		return configured
	}
	if executable, err := os.Executable(); err == nil {
		sibling := filepath.Join(filepath.Dir(executable), "ztasks-core")
		if _, err := os.Stat(sibling); err == nil {
			return sibling
		}
	}
	return filepath.Join(projectRoot, "core", "zig-out", "bin", "ztasks-core")
}

func newRequestID() string {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "ztasks-cli-request"
	}
	return hex.EncodeToString(value[:])
}
