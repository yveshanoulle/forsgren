package main

import "io"

// checkNeeds checks the needs of the running version against the
// installation's checkout (the working directory) and its config, writes the
// setup issue through reportSetup with the job's token, and records
// setupStatus in --status (forsgren#73, step 15). It exits 0 once its flags
// are valid, whatever the write did, and 2 on a usage error. A stub: it does
// nothing yet.
func checkNeeds(_ []string, _, _ io.Writer) int {
	return 0
}
