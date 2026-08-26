//go:build !windows

package agent

import "os/exec"

func configureHidden(_ *exec.Cmd) {}
