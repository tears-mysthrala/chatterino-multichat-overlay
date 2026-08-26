package main

import (
	"reflect"
	"testing"
)

func TestFlagsFirstAllowsTrailingFlags(t *testing.T) {
	got := flagsFirst([]string{"gilraennr", "Ana", "hola", "--platform", "kick", "--port=9000"}, map[string]bool{
		"--platform": true, "--port": true,
	})
	want := []string{"--platform", "kick", "--port=9000", "gilraennr", "Ana", "hola"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %#v, want %#v", got, want)
	}
}
