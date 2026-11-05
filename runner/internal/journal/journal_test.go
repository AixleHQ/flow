package journal

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

var t0 = time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)

func op(id, seq int64) protocol.Op {
	return protocol.Op{ID: id, Sequence: seq, Op: "image.ensure", DeadlineAt: t0.Add(5 * time.Minute)}
}

func TestEmptyJournalStartsAtZero(t *testing.T) {
	j, err := Open(t.TempDir(), func() time.Time { return t0 })
	if err != nil {
		t.Fatal(err)
	}
	if j.After() != 0 {
		t.Fatalf("after is %d", j.After())
	}
	if _, ok := j.Lookup(1); ok {
		t.Fatal("an empty journal knows an op")
	}
}

func TestEntriesAndAfterSurviveAReopen(t *testing.T) {
	dir := t.TempDir()
	clock := func() time.Time { return t0 }
	j, _ := Open(dir, clock)
	if err := j.Begin(op(1031, 7)); err != nil {
		t.Fatal(err)
	}
	result := protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"pulled": true}}
	if err := j.Finish(1031, result); err != nil {
		t.Fatal(err)
	}
	if j.After() != 0 {
		t.Fatal("after moved before the result was accepted")
	}
	if err := j.Begin(op(1032, 8)); err != nil {
		t.Fatal(err)
	}

	reopened, err := Open(dir, clock)
	if err != nil {
		t.Fatal(err)
	}
	e, ok := reopened.Lookup(1031)
	if !ok || e.Result == nil || e.Result.Status != protocol.StatusOK || e.Result.Data["pulled"] != true || e.Accepted {
		t.Fatalf("entry %#v", e)
	}
	if e, ok := reopened.Lookup(1032); !ok || e.Result != nil {
		t.Fatalf("an op begun but not finished reads %#v", e)
	}

	if err := reopened.Acknowledge(1031); err != nil {
		t.Fatal(err)
	}
	again, _ := Open(dir, clock)
	if again.After() != 7 {
		t.Fatalf("after is %d", again.After())
	}
	if e, _ := again.Lookup(1031); !e.Accepted {
		t.Fatal("the acknowledgement was not persisted")
	} else if e.Result != nil {
		t.Fatalf("the settled result is still kept: %#v", e.Result)
	}
}

func TestAfterNeverMovesBack(t *testing.T) {
	j, _ := Open(t.TempDir(), func() time.Time { return t0 })
	_ = j.Record(op(2, 9), protocol.Result{Status: protocol.StatusExpired})
	_ = j.Record(op(1, 8), protocol.Result{Status: protocol.StatusExpired})
	_ = j.Acknowledge(2)
	_ = j.Acknowledge(1)
	if j.After() != 9 {
		t.Fatalf("after is %d", j.After())
	}
}

func TestEntriesAreKeptFor24Hours(t *testing.T) {
	dir := t.TempDir()
	now := t0
	clock := func() time.Time { return now }
	j, _ := Open(dir, clock)
	_ = j.Record(op(1, 1), protocol.Result{Status: protocol.StatusOK})
	_ = j.Acknowledge(1)
	// Op 2 was begun and op 3 has a result, but neither result was accepted.
	_ = j.Begin(op(2, 2))
	_ = j.Record(op(3, 3), protocol.Result{Status: protocol.StatusOK})

	now = t0.Add(Retention - time.Minute)
	j, _ = Open(dir, clock)
	if _, ok := j.Lookup(1); !ok {
		t.Fatal("pruned before 24 h")
	}

	now = t0.Add(Retention + time.Minute)
	j, _ = Open(dir, clock)
	if _, ok := j.Lookup(1); ok {
		t.Fatal("kept after 24 h")
	}
	for _, id := range []int64{2, 3} {
		if _, ok := j.Lookup(id); !ok {
			t.Fatalf("pruned op %d, whose result was never accepted", id)
		}
	}
	if j.After() != 1 {
		t.Fatal("pruning lost `after`")
	}
}

func TestTheFileIsPrivate(t *testing.T) {
	dir := t.TempDir()
	j, _ := Open(dir, nil)
	_ = j.Record(op(1, 1), protocol.Result{Status: protocol.StatusOK})
	info, err := os.Stat(filepath.Join(dir, FileName))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", info.Mode().Perm())
	}
}

func TestDelete(t *testing.T) {
	dir := t.TempDir()
	j, _ := Open(dir, nil)
	_ = j.Record(op(1, 1), protocol.Result{Status: protocol.StatusOK})
	if err := Delete(dir); err != nil {
		t.Fatal(err)
	}
	if err := Delete(dir); err != nil {
		t.Fatal("deleting a missing journal failed")
	}
}

func TestACorruptJournalIsAnError(t *testing.T) {
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, FileName), []byte("{"), 0o600)
	if _, err := Open(dir, nil); err == nil {
		t.Fatal("a corrupt journal was opened as empty, which would run its ops again")
	}
}
