// Package buildversion names the one value a forsgren binary reports as its
// version when its build gives no release version (forsgren#340): a
// development build says what it is, never an older release.
package buildversion

// Dev is the version of a build whose release version is unknown: no ldflags
// value and no release tag in its build information. It is no release, so
// nothing compares it with one.
const Dev = "dev"
