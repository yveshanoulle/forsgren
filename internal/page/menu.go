package page

// The menu at the top of every page (forsgren#128, decision #133) and the
// pages it leaves out: a hidden page is not written, an unlisted one is
// written without a menu entry and asks search engines to skip it
// (forsgren#159, #200).

// Noindex says whether the page asks search engines to skip it: an unlisted
// page does (forsgren#200).
func (p pageData) Noindex() bool { return p.Unlisted[p.listedAs()] }

// listedAs is the name the site lists the page under, in Hidden and Unlisted:
// the folder of a page in a folder, whose Page is index, else its own name.
func (p pageData) listedAs() string {
	if p.Base == viewBase {
		return p.View
	}
	return p.Page
}

// listed says whether the menu names the page of that name: one the site
// writes (not Hidden) and lists (not Unlisted, forsgren#200).
func (p pageData) listed(name string) bool { return !p.Hidden[name] && !p.Unlisted[name] }

// DataLinked says the footer links the Data page (forsgren#582): the site
// writes and lists it, data_page true.
func (p pageData) DataLinked() bool { return p.listed(DataPage) }

// footerPages are the pages the footer links on every page, in its order
// (forsgren#128, decision #133, forsgren#370).
var footerPages = []rootPage{{settingsPage, "Settings"}, {legendPage, "Legend"}, {dictionaryPage, "Dictionary"}}

// Footer is the footer's line of links: Settings, Legend and Dictionary, then
// Data while DataLinked (forsgren#582). As in the menu, the page's own entry
// is marked "page" and every other entry is a link (forsgren#596).
func (p pageData) Footer() []menuItem {
	pages := footerPages
	if p.DataLinked() {
		pages = append(pages[:len(pages):len(pages)], rootPage{DataPage, "Data"})
	}
	footer := make([]menuItem, len(pages))
	for i, page := range pages {
		footer[i] = menuItem{page.Name + ".html", page.Label, markIf(page.Name == p.Page, "page")}
	}
	return footer
}

// menuItem is one entry of the menu: its address from the root, its label,
// and its aria-current, empty for an entry that is a link.
type menuItem struct{ Href, Label, Current string }

// Menu is the menu at the top of the page (forsgren#128, decision #133): the
// folderPages, then the rootPages, each one the site shows (forsgren#159,
// forsgren#55). The view the page shows is marked current, and the root page
// the page is marked "page"; every other entry is a link.
func (p pageData) Menu() []menuItem {
	return append(p.folderEntries(), p.rootEntries()...)
}

// folderEntries are the menu's entries of the folderPages the site lists,
// the one the page shows marked as viewCurrent says.
func (p pageData) folderEntries() []menuItem {
	menu := make([]menuItem, 0, len(folderPages)+len(rootPages))
	for _, folder := range folderPages {
		if p.listed(folder.Name) {
			menu = append(menu, menuItem{folder.Name + "/", folder.Label, markIf(folder.Name == p.View, p.viewCurrent())})
		}
	}
	return menu
}

// rootEntries are the menu's entries of the rootPages the site lists, the
// page's own marked "page".
func (p pageData) rootEntries() []menuItem {
	menu := make([]menuItem, 0, len(rootPages))
	for _, root := range rootPages {
		if p.listed(root.Name) {
			menu = append(menu, menuItem{root.Name + ".html", root.Label, markIf(root.Name == p.Page, "page")})
		}
	}
	return menu
}

// markIf is mark when on, else empty: the aria-current mark of the entry the
// page is on, or the class of a Week cell with the highest value of its row.
func markIf(on bool, mark string) string {
	if on {
		return mark
	}
	return ""
}

// viewCurrent is the menu's aria-current for the view the page shows: "page"
// on the view's own page, "true" on the root, which shows the view but is not
// its page (Yves's ruling, forsgren#46).
func (p pageData) viewCurrent() string {
	if p.Base == viewBase {
		return "page"
	}
	return "true"
}
