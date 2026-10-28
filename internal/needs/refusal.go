package needs

import "strings"

// Refusal is one configuration setting forsgren refused: the setup issue's
// item for it (forsgren#538). The facts are those the settings page shows:
// the key, the value as written, why it is not accepted and the default in
// force. A reason is a sentence fragment without its closing period, so a
// further reason (a separator conflict that reverted both separators,
// forsgren#536) is one more Refusal and needs no change here.
type Refusal struct {
	Key, Written, Reason, Default string
}

// Item is the refusal as one line of the setup issue, in the words of the
// settings page: `key`: `value` is not accepted: reason. Using the default
// `d`. An empty value reads (empty). The value is configuration text written
// by the installation, so it goes in a code span (no mention or link in it
// acts) and loses what could leave the span or the line.
func (r Refusal) Item() string {
	return "`" + r.Key + "`: `" + spanText(r.Written) + "` is not accepted: " + r.Reason +
		". Using the default `" + spanText(r.Default) + "`."
}

// spanText is text fit for a one-line code span: a backtick becomes an
// apostrophe, a line break or control character a space, and nothing at all
// reads (empty).
func spanText(text string) string {
	if text == "" {
		return "(empty)"
	}
	return strings.Map(func(c rune) rune {
		switch {
		case c == '`':
			return '\''
		case c < ' ' || c == 0x7f:
			return ' '
		}
		return c
	}, text)
}
