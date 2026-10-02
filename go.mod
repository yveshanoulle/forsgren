module github.com/yveshanoulle/forsgren

go 1.26.1

toolchain go1.27.1

// npm ships Go code without its own go.mod (node_modules/flatted/golang), so
// without this line ./... and go mod tidy count it as forsgren's own package.
// Scripts/check_go_tests.sh is red when it goes.
ignore node_modules
