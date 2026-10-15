package config

import (
	"strings"

	"go.yaml.in/yaml/v3"
)

// maxWritten is how many characters of a list or mapping a Rejection shows
// as the value as written (forsgren#183).
const maxWritten = 40

// writtenOf is the value of a setting as the file writes it, for a Rejection
// to show: a scalar as it is, a list or mapping in YAML's flow form, `[a, b]`
// or `{a: b}`, on one line and cut to maxWritten characters and three dots.
func writtenOf(n yaml.Node) string {
	if n.Kind != yaml.SequenceNode && n.Kind != yaml.MappingNode {
		return n.Value
	}
	text := flow(&n)
	if runes := []rune(text); len(runes) > maxWritten {
		return string(runes[:maxWritten]) + "..."
	}
	return text
}

// flow is the node in YAML's flow form, on one line.
func flow(n *yaml.Node) string {
	switch n.Kind {
	case yaml.SequenceNode:
		return "[" + strings.Join(flows(n.Content), ", ") + "]"
	case yaml.MappingNode:
		pairs := make([]string, 0, len(n.Content)/2)
		for i := 0; i+1 < len(n.Content); i += 2 {
			pairs = append(pairs, flow(n.Content[i])+": "+flow(n.Content[i+1]))
		}
		return "{" + strings.Join(pairs, ", ") + "}"
	case yaml.AliasNode:
		return "*" + n.Value
	}
	return strings.Join(strings.Fields(n.Value), " ")
}

// flows are the nodes in flow form, in order.
func flows(nodes []*yaml.Node) []string {
	out := make([]string, len(nodes))
	for i, n := range nodes {
		out[i] = flow(n)
	}
	return out
}
