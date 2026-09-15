package coreclient

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sync"

	"github.com/hib2018/ztasks/app/internal/protocol"
)

var (
	ErrMismatchedResponse = errors.New("core response identity mismatch")
	ErrCoreClosed         = errors.New("core process is closed")
)

type Client struct {
	command *exec.Cmd
	stdin   io.WriteCloser
	stdout  *bufio.Scanner
	mu      sync.Mutex
	closed  bool
}

func Start(corePath, projectRoot, source string) (*Client, error) {
	command := commandFor(corePath, projectRoot, source)
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("open core stdin: %w", err)
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		stdin.Close()
		return nil, fmt.Errorf("open core stdout: %w", err)
	}
	if err := command.Start(); err != nil {
		stdin.Close()
		return nil, fmt.Errorf("start core: %w", err)
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), protocol.MaxLineSize)
	return &Client{command: command, stdin: stdin, stdout: scanner}, nil
}

func commandFor(corePath, projectRoot, source string) *exec.Cmd {
	arguments := []string{"serve", "--project-root", projectRoot}
	if source != "" {
		arguments = append(arguments, "--source", source)
	}
	return exec.Command(corePath, arguments...)
}

func (client *Client) Call(request protocol.Request) (protocol.Response, error) {
	client.mu.Lock()
	defer client.mu.Unlock()
	if client.closed {
		return protocol.Response{}, ErrCoreClosed
	}
	encoded, err := json.Marshal(request)
	if err != nil {
		return protocol.Response{}, fmt.Errorf("encode core request: %w", err)
	}
	encoded = append(encoded, '\n')
	if _, err := client.stdin.Write(encoded); err != nil {
		return protocol.Response{}, fmt.Errorf("write core request: %w", err)
	}
	if !client.stdout.Scan() {
		if err := client.stdout.Err(); err != nil {
			return protocol.Response{}, fmt.Errorf("read core response: %w", err)
		}
		return protocol.Response{}, io.ErrUnexpectedEOF
	}
	return decodeCorrelatedResponse(request.RequestID, client.stdout.Bytes())
}

func decodeCorrelatedResponse(requestID string, line []byte) (protocol.Response, error) {
	envelope, err := protocol.DecodeLine(line)
	if err != nil {
		return protocol.Response{}, err
	}
	if envelope.Response == nil || envelope.Response.RequestID != requestID || envelope.Response.Version != protocol.Version {
		return protocol.Response{}, ErrMismatchedResponse
	}
	return *envelope.Response, nil
}

func (client *Client) Close() error {
	client.mu.Lock()
	if client.closed {
		client.mu.Unlock()
		return nil
	}
	client.closed = true
	err := client.stdin.Close()
	client.mu.Unlock()
	waitErr := client.command.Wait()
	if err != nil {
		return err
	}
	return waitErr
}
