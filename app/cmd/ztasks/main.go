package main

import (
	"os"

	"github.com/hib2018/ztasks/app/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], os.Stdout, os.Stderr))
}
