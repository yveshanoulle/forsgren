package page

// incompleteView is what the "bugsincomplete" template shows in place of a
// bug number that cannot be trusted, because a repository's bug list was too
// long to read in full (forsgren#140, forsgren#202): Column, the column it
// stands in, which its aria-label names, and Hidden, what is not shown, which
// its title names.
type incompleteView struct {
	Column, Hidden string
}

// incompleteViewOf is the view for column, which hides hidden: the template
// function "incomplete".
func incompleteViewOf(column, hidden string) incompleteView {
	return incompleteView{Column: column, Hidden: hidden}
}
