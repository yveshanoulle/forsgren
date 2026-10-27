package page

import (
	"bytes"
	"errors"
	"fmt"
	"io"
)

// Render writes the named page, filled with data, to w, its counts of 1000 or
// more written with the separator of data.ThousandsSeparator (forsgren#528).
func Render(w io.Writer, name string, data Data) error {
	p, ok := pages[name]
	if !ok {
		return fmt.Errorf("page %q not found", name)
	}
	shown := pageData{Data: data, Base: p.base, View: p.viewShown(data), Page: p.name()}
	var page bytes.Buffer
	err := p.set.ExecuteTemplate(&page, p.file, shown)
	_, werr := io.WriteString(w, withSeparator(page.String(), data.ThousandsSeparator))
	return errors.Join(err, werr)
}
