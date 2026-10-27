package config

// The paths of a service (forsgren#496, decision #497 A): the folders and
// files of the repository whose changes belong to the service. A service is
// written as a label alone, or as a label with paths:
//
//	services:
//	  deploy-ios: IOS
//	  deploy-api: {label: API, paths: [api/, shared/]}
//
// A path is relative to the repository root: a folder ends in /, a file is
// its name with the folders before it. No glob, no absolute path, no ..
// (no part of the codebase matches globs, so none is invented here).

import (
	"errors"
	"fmt"
	"strings"

	"go.yaml.in/yaml/v3"
)

var (
	errNoPaths   = errors.New("paths lists no path; write folders and files, or leave paths out")
	errPathEmpty = errors.New("a path is empty")
)

const (
	serviceShape  = "line %d: a service is a label or {label, paths}"
	pathsShape    = "line %d: paths is a list of folders and files"
	unknownSvcKey = "line %d: unknown key %q"
)

// service is a task's value as the file writes it. given says the paths key
// was written, so `paths: []` is told from no paths.
type service struct {
	label text
	paths []text
	given bool
}

// UnmarshalYAML takes a label alone or a mapping of label and paths.
func (s *service) UnmarshalYAML(n *yaml.Node) error {
	switch n.Kind {
	case yaml.ScalarNode:
		return s.label.UnmarshalYAML(n)
	case yaml.MappingNode:
		return s.fromMapping(n)
	}
	return typeError(serviceShape, n.Line)
}

func (s *service) fromMapping(n *yaml.Node) error {
	for i := 0; i+1 < len(n.Content); i += 2 {
		key, value := n.Content[i], n.Content[i+1]
		var err error
		switch key.Value {
		case "label":
			err = s.label.UnmarshalYAML(value)
		case "paths":
			err = s.readPaths(value)
		default:
			err = typeError(unknownSvcKey, key.Line, key.Value)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *service) readPaths(n *yaml.Node) error {
	s.given = true
	if n.ShortTag() == "!!null" {
		return nil
	}
	if n.Kind != yaml.SequenceNode {
		return typeError(pathsShape, n.Line)
	}
	for _, item := range n.Content {
		var p text
		if err := p.UnmarshalYAML(item); err != nil {
			return err
		}
		s.paths = append(s.paths, p)
	}
	return nil
}

func typeError(format string, args ...any) error {
	return &yaml.TypeError{Errors: []string{fmt.Sprintf(format, args...)}}
}

// checkPaths refuses an empty list, a path that is not a plain
// repository-relative folder or file, or one listed twice.
func (s service) checkPaths() ([]string, error) {
	if !s.given {
		return nil, nil
	}
	if len(s.paths) == 0 {
		return nil, errNoPaths
	}
	seen := map[string]bool{}
	out := make([]string, 0, len(s.paths))
	for _, p := range s.paths {
		path := string(p)
		if err := checkPath(path); err != nil {
			return nil, err
		}
		if seen[path] {
			return nil, fmt.Errorf("path %q is listed twice", path)
		}
		seen[path] = true
		out = append(out, path)
	}
	return out, nil
}

// checkPath says why a path is no folder or file of the repository.
func checkPath(path string) error {
	if err := checkPathText(path); err != nil {
		return err
	}
	for _, part := range strings.Split(strings.TrimSuffix(path, "/"), "/") {
		switch part {
		case "..":
			return fmt.Errorf("path %q has a .. part; write it from the repository root", path)
		case "", ".":
			return fmt.Errorf("path %q has a . or empty part", path)
		}
	}
	return nil
}

// checkPathText refuses a path by how it is written as a whole.
func checkPathText(path string) error {
	switch {
	case strings.TrimSpace(path) == "":
		return errPathEmpty
	case strings.Contains(path, `\`):
		return fmt.Errorf("path %q uses a backslash; write / between folders", path)
	case strings.HasPrefix(path, "/"):
		return fmt.Errorf("path %q is absolute; write it from the repository root", path)
	case strings.ContainsAny(path, "*?[{"):
		return fmt.Errorf("path %q holds a glob character; write a folder or a file name", path)
	}
	return nil
}
