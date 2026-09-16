package coreclient

import (
	"bufio"
	"context"
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
	writeMu sync.Mutex
	stateMu sync.Mutex
	pending map[string]chan callResult
	fatal   error
	done    chan struct{}
	closed  bool
}

type callResult struct {
	response protocol.Response
	err      error
}

func Start(corePath, projectRoot, source string) (*Client, error) {
	return startProcess(commandFor(corePath, projectRoot, source))
}

func startProcess(command *exec.Cmd) (*Client, error) {
	stdin, err := command.StdinPipe()
	if err != nil {
		return nil, fmt.Errorf("open core stdin: %w", err)
	}
	stdout, err := command.StdoutPipe()
	if err != nil {
		stdin.Close()
		return nil, fmt.Errorf("open core stdout: %w", err)
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		stdin.Close()
		return nil, fmt.Errorf("open core stderr: %w", err)
	}
	if err := command.Start(); err != nil {
		stdin.Close()
		return nil, fmt.Errorf("start core: %w", err)
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), protocol.MaxLineSize)
	client := &Client{
		command: command,
		stdin:   stdin,
		pending: make(map[string]chan callResult),
		done:    make(chan struct{}),
	}
	go func() { _, _ = io.Copy(io.Discard, stderr) }()
	go client.readResponses(scanner)
	return client, nil
}

func commandFor(corePath, projectRoot, source string) *exec.Cmd {
	arguments := []string{"serve", "--project-root", projectRoot}
	if source != "" {
		arguments = append(arguments, "--source", source)
	}
	return exec.Command(corePath, arguments...)
}

func (client *Client) Call(request protocol.Request) (protocol.Response, error) {
	return client.CallContext(context.Background(), request)
}

func (client *Client) CallContext(ctx context.Context, request protocol.Request) (protocol.Response, error) {
	encoded, err := json.Marshal(request)
	if err != nil {
		return protocol.Response{}, fmt.Errorf("encode core request: %w", err)
	}
	resultChannel := make(chan callResult, 1)
	client.stateMu.Lock()
	if client.closed {
		client.stateMu.Unlock()
		return protocol.Response{}, ErrCoreClosed
	}
	if client.fatal != nil {
		err := client.fatal
		client.stateMu.Unlock()
		return protocol.Response{}, err
	}
	if _, exists := client.pending[request.RequestID]; exists {
		client.stateMu.Unlock()
		return protocol.Response{}, fmt.Errorf("request %s is already pending", request.RequestID)
	}
	client.pending[request.RequestID] = resultChannel
	client.stateMu.Unlock()

	encoded = append(encoded, '\n')
	client.writeMu.Lock()
	if _, err := client.stdin.Write(encoded); err != nil {
		client.writeMu.Unlock()
		client.removePending(request.RequestID, resultChannel)
		return protocol.Response{}, fmt.Errorf("write core request: %w", err)
	}
	client.writeMu.Unlock()

	select {
	case result := <-resultChannel:
		return result.response, result.err
	case <-ctx.Done():
		client.removePending(request.RequestID, resultChannel)
		return protocol.Response{}, ctx.Err()
	case <-client.done:
		client.stateMu.Lock()
		err := client.fatal
		client.stateMu.Unlock()
		if err == nil {
			err = io.ErrUnexpectedEOF
		}
		return protocol.Response{}, err
	}
}

func (client *Client) readResponses(scanner *bufio.Scanner) {
	for scanner.Scan() {
		envelope, err := protocol.DecodeLine(scanner.Bytes())
		if err != nil || envelope.Response == nil {
			client.failConnection(fmt.Errorf("decode core response: %w", err))
			return
		}
		response := *envelope.Response
		client.stateMu.Lock()
		channel, found := client.pending[response.RequestID]
		if found {
			delete(client.pending, response.RequestID)
			client.stateMu.Unlock()
			channel <- callResult{response: response}
			continue
		}
		if len(client.pending) != 0 {
			client.stateMu.Unlock()
			client.failConnection(ErrMismatchedResponse)
			return
		}
		client.stateMu.Unlock()
	}
	if err := scanner.Err(); err != nil {
		client.failConnection(fmt.Errorf("read core response: %w", err))
	} else {
		client.failConnection(io.ErrUnexpectedEOF)
	}
}

func (client *Client) removePending(id string, channel chan callResult) {
	client.stateMu.Lock()
	if current, exists := client.pending[id]; exists && current == channel {
		delete(client.pending, id)
	}
	client.stateMu.Unlock()
}

func (client *Client) failConnection(err error) {
	client.stateMu.Lock()
	if client.fatal == nil {
		client.fatal = err
		for id, channel := range client.pending {
			delete(client.pending, id)
			channel <- callResult{err: err}
		}
		close(client.done)
	}
	client.stateMu.Unlock()
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
	client.stateMu.Lock()
	if client.closed {
		client.stateMu.Unlock()
		return nil
	}
	client.closed = true
	err := client.stdin.Close()
	client.stateMu.Unlock()
	waitErr := client.command.Wait()
	if err != nil {
		return err
	}
	return waitErr
}
