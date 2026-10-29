package page

import (
	"bytes"
	"errors"
	"fmt"
	"io"
)

// Render writes the named page, filled with data, to w, its counts of 1000 or
// more and its decimals written with the separators of data.ThousandsSeparator
// and data.DecimalSeparator (forsgren#528, #536).
func Render(w io.Writer, name string, data Data) error {
	p, ok := pages[name]
	if !ok {
		return fmt.Errorf("page %q not found", name)
	}
	shown := pageData{Data: data, Base: p.base, View: p.viewShown(data), Page: p.name()}
	var page bytes.Buffer
	err := p.set.ExecuteTemplate(&page, p.file, shown)
	text, lerr := withEntryLinks(page.String(), p)
	_, werr := io.WriteString(w, withSeparators(text, data))
	return errors.Join(err, lerr, werr)
}
