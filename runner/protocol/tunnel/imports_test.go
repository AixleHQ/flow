package tunnel

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// The package is shared with the relay service and extracted with the runner
// (DESIGN.md §14.1): it imports the standard library, and the WebSocket library in
// wsconn.go only, and nothing from runner/internal.
func TestImportsStayInsideTheRules(t *testing.T) {
	files, err := filepath.Glob("*.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("no sources: %v", err)
	}
	fset := token.NewFileSet()
	for _, name := range files {
		if strings.HasSuffix(name, "_test.go") {
			continue
		}
		src, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		f, err := parser.ParseFile(fset, name, src, parser.ImportsOnly)
		if err != nil {
			t.Fatal(err)
		}
		for _, imp := range f.Imports {
			path, _ := strconv.Unquote(imp.Path.Value)
			first, _, _ := strings.Cut(path, "/")
			switch {
			case !strings.Contains(first, "."): // the standard library
			case path == "github.com/coder/websocket" && name == "wsconn.go":
			default:
				t.Errorf("%s imports %q: only the standard library, and coder/websocket in wsconn.go", name, path)
			}
		}
	}
}

// The test files may use the WebSocket library, and nothing else outside the
// standard library, so that the dependency graph the runner ships stays as it is.
func TestTestsImportOnlyTheStandardLibraryAndWebSocket(t *testing.T) {
	files, _ := filepath.Glob("*_test.go")
	fset := token.NewFileSet()
	for _, name := range files {
		f, err := parser.ParseFile(fset, name, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatal(err)
		}
		for _, imp := range f.Imports {
			path, _ := strconv.Unquote(imp.Path.Value)
			first, _, _ := strings.Cut(path, "/")
			if strings.Contains(first, ".") && path != "github.com/coder/websocket" {
				t.Errorf("%s imports %q", name, path)
			}
		}
	}
}
