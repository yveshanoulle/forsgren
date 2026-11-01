package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"go/types"
	"io/fs"
	"math"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"testing"
)

// The checker behind TestNoUnboundedConversionOfA64BitParse (forsgren#608).
// CodeQL's go/incorrect-integer-conversion runs only on GitHub after a push,
// and golangci-lint's gosec G115 does not report this pattern (measured on
// forsgren#608, also for GOARCH=386), so this test is the local guard.
//
// What it judges, per package (the non-test .go files of one directory):
//   - a source is a call of strconv.ParseInt or strconv.ParseUint whose
//     bitSize is the literal 64, or (wrappers) a call of a function of the
//     same package, by name, that returns int64 or uint64 and returns a value
//     taken from a source (found again until nothing changes, so a wrapper of
//     a wrapper counts);
//   - a value is taken from a source when it is the first left-hand side of
//     an assignment (=, :=, var) whose one right-hand side is a source call;
//     it is named by its expression as written (n, p.Commits);
//   - a finding is a conversion to int, int8, int16, int32, uint, uint8,
//     uint16, uint32 or uintptr of such a value, or of a source call itself,
//     unless (bounds) the same function compares that expression (<, <=, >,
//     >=) with a math.Max constant no larger than the type's maximum on a
//     32-bit build, earlier in the source than the conversion.
//
// Its limits, on purpose, to stay small and explicit: names, not objects
// (go/types is not run), so a shadowed name or a copy (m := n) is not
// followed; no flow: a bound in any branch before the conversion counts;
// the lower bound and a sign change (uint64 to int64) are not judged, as
// CodeQL's rule judges the upper bound; a wrapper of another package is not
// a source; a function body is judged alone, a function literal too.
// Fixtures pin each rule; the mutation proofs in intconversion_test.go show
// the bound rule and the wrapper tracking are needed.

// convChecker judges the conversions of one package. bounds and wrappers
// are false only in the mutation proofs.
type convChecker struct {
	bounds, wrappers bool
	wide             map[string]string
}

// fileAt is a parsed file and the name its findings carry.
type fileAt struct {
	file *ast.File
	name string
}

// typeMax is the largest value of each narrow type on a 32-bit build.
var typeMax = map[string]uint64{
	"int": math.MaxInt32, "int8": math.MaxInt8, "int16": math.MaxInt16, "int32": math.MaxInt32,
	"uint": math.MaxUint32, "uint8": math.MaxUint8, "uint16": math.MaxUint16,
	"uint32": math.MaxUint32, "uintptr": math.MaxUint32,
}

// boundMax is the value of each math.Max constant a bound may name; MaxInt
// and MaxUint are 64-bit on a 64-bit build.
var boundMax = map[string]uint64{
	"math.MaxInt8": math.MaxInt8, "math.MaxInt16": math.MaxInt16, "math.MaxInt32": math.MaxInt32,
	"math.MaxInt64": math.MaxInt64, "math.MaxInt": math.MaxInt64,
	"math.MaxUint8": math.MaxUint8, "math.MaxUint16": math.MaxUint16, "math.MaxUint32": math.MaxUint32,
	"math.MaxUint64": math.MaxUint64, "math.MaxUint": math.MaxUint64,
}

// moduleRoot is the module's root from this package's directory, where go
// test runs; findings name files from it.
const moduleRoot = "../.."

// checkModuleConversions judges every non-test .go file under dir, one
// package per directory, and says how many files it judged.
func checkModuleConversions(t *testing.T, dir string, checker convChecker) ([]string, int) {
	t.Helper()
	w := goWalk{fset: token.NewFileSet(), packages: map[string][]fileAt{}}
	if err := filepath.WalkDir(dir, w.visit); err != nil {
		t.Fatalf("walking %s: %v", dir, err)
	}
	var findings []string
	for _, pkg := range w.packages {
		findings = append(findings, checker.check(w.fset, pkg)...)
	}
	sort.Strings(findings)
	return findings, w.files
}

// goWalk gathers the parsed non-test Go files of a tree by directory.
type goWalk struct {
	fset     *token.FileSet
	packages map[string][]fileAt
	files    int
}

// visit parses path when it is a non-test Go file and skips the
// directories that hold no module code.
func (w *goWalk) visit(path string, d fs.DirEntry, err error) error {
	if err != nil {
		return err
	}
	if d.IsDir() {
		return skippedDir(d.Name())
	}
	if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
		return nil
	}
	file, err := parser.ParseFile(w.fset, path, nil, 0)
	name, _ := filepath.Rel(moduleRoot, path)
	w.packages[filepath.Dir(path)] = append(w.packages[filepath.Dir(path)], fileAt{file, filepath.ToSlash(name)})
	w.files++
	return err
}

// skippedDir is fs.SkipDir for a directory that holds no module code: a
// hidden one (agent worktrees live under .claude), node_modules, testdata.
func skippedDir(name string) error {
	if noModuleCode[name] || hidden(name) {
		return fs.SkipDir
	}
	return nil
}

// noModuleCode are the directory names that never hold module code.
var noModuleCode = map[string]bool{"node_modules": true, "testdata": true}

// hidden says whether name is a hidden directory, not the . or .. of a path.
func hidden(name string) bool {
	return strings.HasPrefix(name, ".") && strings.Trim(name, ".") != ""
}

// check judges the files of one package.
func (c convChecker) check(fset *token.FileSet, files []fileAt) []string {
	c.wide = c.wideFuncs(files)
	var findings []string
	for _, f := range files {
		findings = append(findings, c.judgeFile(fset, f)...)
	}
	return uniqueSorted(findings)
}

// judgeFile lists the findings of every function body of f; a function
// literal is judged in its own body and in the one around it.
func (c convChecker) judgeFile(fset *token.FileSet, f fileAt) []string {
	var findings []string
	for _, body := range bodiesOf(f.file) {
		findings = append(findings, c.judge(fset, f.name, body)...)
	}
	return findings
}

// uniqueSorted is findings sorted, each once.
func uniqueSorted(findings []string) []string {
	sort.Strings(findings)
	return slices.Compact(findings)
}

// bodiesOf are the bodies of every function and function literal of file.
func bodiesOf(file *ast.File) []*ast.BlockStmt {
	var bodies []*ast.BlockStmt
	ast.Inspect(file, func(n ast.Node) bool {
		switch fn := n.(type) {
		case *ast.FuncDecl:
			bodies = appendBody(bodies, fn.Body)
		case *ast.FuncLit:
			bodies = appendBody(bodies, fn.Body)
		}
		return true
	})
	return bodies
}

// appendBody adds body unless the function has none (an assembly stub).
func appendBody(bodies []*ast.BlockStmt, body *ast.BlockStmt) []*ast.BlockStmt {
	if body == nil {
		return bodies
	}
	return append(bodies, body)
}

// wideFuncs are the package's functions that return a 64-bit parse result,
// each with the source it returns, found until nothing changes.
func (c convChecker) wideFuncs(files []fileAt) map[string]string {
	c.wide = map[string]string{}
	for grown := c.wrappers; grown; {
		grown = false
		for _, fn := range funcDecls(files) {
			if origin, ok := c.returnsSource(fn); ok && c.wide[fn.Name.Name] == "" {
				c.wide[fn.Name.Name] = origin
				grown = true
			}
		}
	}
	return c.wide
}

// funcDecls are the package's top-level functions with a body.
func funcDecls(files []fileAt) []*ast.FuncDecl {
	var decls []*ast.FuncDecl
	for _, f := range files {
		for _, d := range f.file.Decls {
			if fn, ok := d.(*ast.FuncDecl); ok && fn.Body != nil {
				decls = append(decls, fn)
			}
		}
	}
	return decls
}

// returnsSource says whether fn returns int64 or uint64 and a value taken
// from a source, and which.
func (c convChecker) returnsSource(fn *ast.FuncDecl) (string, bool) {
	if !hasWideResult(fn.Type.Results) {
		return "", false
	}
	taken := c.takenIn(fn.Body)
	origin := ""
	ast.Inspect(fn.Body, func(n ast.Node) bool {
		if ret, ok := n.(*ast.ReturnStmt); ok {
			origin = firstTaken(taken, ret.Results, origin)
		}
		return true
	})
	return origin, origin != ""
}

// firstTaken is origin, or the source of the first of results taken from one.
func firstTaken(taken map[string]string, results []ast.Expr, origin string) string {
	for _, r := range results {
		if origin == "" {
			origin = taken[types.ExprString(r)]
		}
	}
	return origin
}

// hasWideResult says whether results name int64 or uint64.
func hasWideResult(results *ast.FieldList) bool {
	if results == nil {
		return false
	}
	for _, field := range results.List {
		if name := types.ExprString(field.Type); name == "int64" || name == "uint64" {
			return true
		}
	}
	return false
}

// source names the source call e is, or "".
func (c convChecker) source(e ast.Expr) string {
	call, ok := e.(*ast.CallExpr)
	if !ok {
		return ""
	}
	if parse64(call) {
		return types.ExprString(call.Fun)
	}
	if id, ok := call.Fun.(*ast.Ident); ok && c.wide[id.Name] != "" {
		return id.Name + " (" + c.wide[id.Name] + ")"
	}
	return ""
}

// parse64 says whether call is strconv.ParseInt or ParseUint with bitSize 64.
func parse64(call *ast.CallExpr) bool {
	if !parsers[types.ExprString(call.Fun)] {
		return false
	}
	bits, ok := call.Args[len(call.Args)-1].(*ast.BasicLit)
	return ok && bits.Value == "64"
}

// parsers are the strconv functions whose bitSize, the last argument, the
// checker reads.
var parsers = map[string]bool{"strconv.ParseInt": true, "strconv.ParseUint": true}

// takenIn maps each expression of body assigned from a source to the source.
func (c convChecker) takenIn(body *ast.BlockStmt) map[string]string {
	taken := map[string]string{}
	ast.Inspect(body, func(n ast.Node) bool {
		switch s := n.(type) {
		case *ast.AssignStmt:
			c.take(taken, s.Lhs[0], s.Rhs)
		case *ast.ValueSpec:
			c.take(taken, s.Names[0], s.Values)
		}
		return true
	})
	return taken
}

// take notes lhs as taken from the one right-hand side when it is a source.
func (c convChecker) take(taken map[string]string, lhs ast.Expr, rhs []ast.Expr) {
	if len(rhs) != 1 {
		return
	}
	if origin := c.source(rhs[0]); origin != "" {
		taken[types.ExprString(lhs)] = origin
	}
}

// judge lists the unbounded conversions of body as "<name>:<line>: <why>".
func (c convChecker) judge(fset *token.FileSet, name string, body *ast.BlockStmt) []string {
	taken := c.takenIn(body)
	var findings []string
	ast.Inspect(body, func(n ast.Node) bool {
		conv, ok := narrowConversion(n)
		if !ok {
			return true
		}
		if why := c.unbounded(body, taken, conv); why != "" {
			findings = append(findings, fmt.Sprintf("%s:%d: %s", name, fset.Position(conv.Pos()).Line, why))
		}
		return true
	})
	return findings
}

// narrowConversion is n when it is a conversion to a narrow type.
func narrowConversion(n ast.Node) (*ast.CallExpr, bool) {
	call, ok := n.(*ast.CallExpr)
	if !ok || len(call.Args) != 1 {
		return nil, false
	}
	id, ok := call.Fun.(*ast.Ident)
	return call, ok && typeMax[id.Name] > 0
}

// unbounded says why conv is a finding, or "".
func (c convChecker) unbounded(body *ast.BlockStmt, taken map[string]string, conv *ast.CallExpr) string {
	arg := conv.Args[0]
	target := types.ExprString(conv.Fun)
	if origin := c.source(arg); origin != "" {
		return fmt.Sprintf("%s converts the 64-bit result of %s straight, with no bound", types.ExprString(conv), origin)
	}
	origin := taken[types.ExprString(arg)]
	if origin == "" || c.bounded(body, conv) {
		return ""
	}
	return fmt.Sprintf("%s converts the 64-bit result of %s with no bound of %s or less compared before it",
		types.ExprString(conv), origin, maxName[target])
}

// bounded says whether the bound rule is on and body bounds conv's value
// before it.
func (c convChecker) bounded(body *ast.BlockStmt, conv *ast.CallExpr) bool {
	if !c.bounds {
		return false
	}
	return boundedBefore(body, conv.Args[0], conv.Pos(), typeMax[types.ExprString(conv.Fun)])
}

// maxName is the math constant of each narrow type's maximum on a 32-bit
// build.
var maxName = map[string]string{
	"int": "math.MaxInt32", "int8": "math.MaxInt8", "int16": "math.MaxInt16", "int32": "math.MaxInt32",
	"uint": "math.MaxUint32", "uint8": "math.MaxUint8", "uint16": "math.MaxUint16",
	"uint32": "math.MaxUint32", "uintptr": "math.MaxUint32",
}

// boundedBefore says whether body compares arg with a math.Max constant of
// at most limit before pos.
func boundedBefore(body *ast.BlockStmt, arg ast.Expr, pos token.Pos, limit uint64) bool {
	want := types.ExprString(arg)
	found := false
	ast.Inspect(body, func(n ast.Node) bool {
		if cmp := orderingBefore(n, pos); cmp != nil {
			found = found || bounds(cmp.X, cmp.Y, want, limit) || bounds(cmp.Y, cmp.X, want, limit)
		}
		return true
	})
	return found
}

// orderingBefore is n when it is an ordering comparison before pos, else nil.
func orderingBefore(n ast.Node, pos token.Pos) *ast.BinaryExpr {
	cmp, ok := n.(*ast.BinaryExpr)
	if !ok || cmp.Pos() >= pos {
		return nil
	}
	if !ordering(cmp.Op) {
		return nil
	}
	return cmp
}

// ordering says whether op compares by order.
func ordering(op token.Token) bool {
	return op == token.LSS || op == token.LEQ || op == token.GTR || op == token.GEQ
}

// bounds says whether value is want and bound a math.Max constant of at
// most limit.
func bounds(value, bound ast.Expr, want string, limit uint64) bool {
	if types.ExprString(value) != want {
		return false
	}
	max, known := boundMax[types.ExprString(bound)]
	return known && max <= limit
}
