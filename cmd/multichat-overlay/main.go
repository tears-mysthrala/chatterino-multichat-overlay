package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/tears-mysthrala/chatterino-multichat-overlay/internal/overlay"
)

const version = "0.1.0"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return serve(nil)
	}
	switch args[0] {
	case "serve":
		return serve(args[1:])
	case "doctor":
		return doctor(args[1:])
	case "url":
		return printURL(args[1:])
	case "emit":
		return emit(args[1:])
	case "help", "-h", "--help":
		printHelp()
		return nil
	case "--version", "version":
		fmt.Println(version)
		return nil
	default:
		return fmt.Errorf("unknown command %q; use --help", args[0])
	}
}

func printHelp() {
	fmt.Printf(`multichat-overlay %s

Local browser-source overlay for Chatterino chat plugins.

Usage:
  multichat-overlay serve [--port 8765]
  multichat-overlay doctor [--port 8765] [--json]
  multichat-overlay url <panel> [--port 8765]
  multichat-overlay emit <panel> <author> <message> [--platform test]
  multichat-overlay --version

OBS URL example:
  http://127.0.0.1:8765/overlay/gilraennr
`, version)
}

func serve(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	port := fs.Int("port", 8765, "loopback HTTP port")
	history := fs.Int("history", 100, "messages retained per panel")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *port < 1024 || *port > 65535 {
		return errors.New("port must be between 1024 and 65535")
	}
	if *history < 1 || *history > 500 {
		return errors.New("history must be between 1 and 500")
	}
	server := overlay.NewServer(*history)
	httpServer := &http.Server{
		Addr: "127.0.0.1:" + strconv.Itoa(*port), Handler: server.Handler(),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second,
		WriteTimeout: 0, IdleTimeout: 60 * time.Second,
	}
	fmt.Printf("Overlay ready: http://127.0.0.1:%d/overlay/gilraennr\n", *port)
	fmt.Println("Press Ctrl-C to stop.")
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errCh := make(chan error, 1)
	go func() { errCh <- httpServer.ListenAndServe() }()
	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		return httpServer.Shutdown(shutdownCtx)
	case err := <-errCh:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

func doctor(args []string) error {
	fs := flag.NewFlagSet("doctor", flag.ContinueOnError)
	port := fs.Int("port", 8765, "loopback HTTP port")
	asJSON := fs.Bool("json", false, "print machine-readable output")
	if err := fs.Parse(args); err != nil {
		return err
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d/health", *port))
	result := map[string]any{"ok": err == nil && resp.StatusCode == 200, "port": *port}
	if err != nil {
		result["error"] = err.Error()
	}
	if resp != nil {
		defer resp.Body.Close()
		result["status"] = resp.StatusCode
	}
	if *asJSON {
		encoded, _ := json.Marshal(result)
		fmt.Println(string(encoded))
	} else if result["ok"] == true {
		fmt.Printf("OK: overlay service is listening on 127.0.0.1:%d\n", *port)
	} else {
		return fmt.Errorf("overlay service is not healthy on port %d", *port)
	}
	return nil
}

func printURL(args []string) error {
	args = flagsFirst(args, map[string]bool{"--port": true, "-port": true})
	fs := flag.NewFlagSet("url", flag.ContinueOnError)
	port := fs.Int("port", 8765, "loopback HTTP port")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 1 || !overlay.ValidPanel(fs.Arg(0)) {
		return errors.New("usage: multichat-overlay url <panel>")
	}
	fmt.Printf("http://127.0.0.1:%d/overlay/%s\n", *port, overlay.NormalizePanel(fs.Arg(0)))
	return nil
}

func emit(args []string) error {
	args = flagsFirst(args, map[string]bool{"--port": true, "-port": true, "--platform": true, "-platform": true})
	fs := flag.NewFlagSet("emit", flag.ContinueOnError)
	port := fs.Int("port", 8765, "loopback HTTP port")
	platform := fs.String("platform", "test", "message platform")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 3 {
		return errors.New("usage: multichat-overlay emit <panel> <author> <message>")
	}
	message := overlay.Message{Panel: fs.Arg(0), Platform: *platform, Author: fs.Arg(1), Text: fs.Arg(2), Kind: "text_message"}
	return overlay.PostMessage(context.Background(), *port, message)
}

// flagsFirst keeps the standard library's strict parser while allowing users
// to put value-taking flags before or after positional arguments.
func flagsFirst(args []string, valueFlags map[string]bool) []string {
	flags, positional := make([]string, 0, len(args)), make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		name := args[i]
		if eq := len(name); eq > 0 {
			for j := 0; j < len(name); j++ {
				if name[j] == '=' {
					name = name[:j]
					break
				}
			}
		}
		if valueFlags[name] {
			flags = append(flags, args[i])
			if name == args[i] && i+1 < len(args) {
				i++
				flags = append(flags, args[i])
			}
		} else {
			positional = append(positional, args[i])
		}
	}
	return append(flags, positional...)
}
