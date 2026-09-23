package cli

import (
	"encoding/json"
	"io/fs"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hib2018/ztasks/app/internal/coreclient"
	"github.com/hib2018/ztasks/app/internal/protocol"
)

func fetchAllStatus(corePath, root string, fallback caller, requestID string) (StatusView, error) {
	var paths []string
	err := filepath.WalkDir(filepath.Join(root, "specs"), func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !entry.IsDir() && entry.Name() == "tasks.md" {
			rel, relErr := filepath.Rel(root, path)
			if relErr == nil {
				paths = append(paths, filepath.ToSlash(rel))
			}
		}
		return nil
	})
	if err != nil || len(paths) < 2 {
		return FetchStatus(fallback, requestID)
	}
	sort.Strings(paths)
	result := StatusView{}
	for i, path := range paths {
		client, startErr := coreclient.Start(corePath, root, path)
		if startErr != nil {
			return StatusView{}, startErr
		}
		id := requestID + "-" + string(rune('a'+i))
		status, fetchErr := FetchStatus(client, id)
		if fetchErr == nil {
			request := readRequest(id+"-digest", "source.validate", "")
			payload, _ := json.Marshal(map[string]string{"locator": path})
			request.Payload = payload
			var response protocol.Response
			response, fetchErr = client.Call(request)
			if fetchErr == nil && !response.OK {
				fetchErr = responseError(response)
			}
			if fetchErr == nil {
				var metadata struct {
					Locator     string `json:"locator"`
					Digest      string `json:"source_digest"`
					PhaseCount  int    `json:"phase_count"`
					TaskCount   int    `json:"task_count"`
					Diagnostics []any  `json:"diagnostics"`
				}
				fetchErr = decodeResult(response.Result, &metadata)
				if fetchErr == nil {
					digest := strings.TrimPrefix(metadata.Digest, "sha256:")
					if len(digest) > 12 {
						digest = digest[:12]
					}
					for j := range status.Tasks {
						status.Tasks[j].Source = path
					}
					result.Sources = append(result.Sources, StatusSource{Path: path, Digest: digest, Tasks: status.Tasks})
					result.Tasks = append(result.Tasks, status.Tasks...)
				}
			}
		}
		_ = client.Close()
		if fetchErr != nil {
			return StatusView{}, fetchErr
		}
	}
	return result, nil
}
