// Package journal makes op execution at-most-once (DESIGN.md §6.7). It records, in
// the runner's state directory, every op the runner has started with its result,
// and the `after` of the long-poll: the highest sequence whose result the gateway
// accepted. A redelivered op is answered from the journal and never run twice,
// and a restarted runner resumes from the persisted `after`.
package journal

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/aixlehq/aixle-runner/internal/fsutil"
	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// FileName is the journal inside the state directory.
const FileName = "journal.json"

// Retention is how long an accepted op is remembered after the runner received it.
// An op whose result was never accepted is remembered until it is.
const Retention = 24 * time.Hour

// Entry is what the journal knows about one op.
type Entry struct {
	Sequence   int64     `json:"sequence"`
	Op         string    `json:"op"`
	ReceivedAt time.Time `json:"received_at"`
	// Result is nil while the op runs. An entry without a result after a restart
	// is an op that was interrupted: it is not run again.
	Result *protocol.Result `json:"result,omitempty"`
	// Accepted is set once the gateway took the result (or answered that the op is
	// not this machine's).
	Accepted bool `json:"accepted,omitempty"`
}

type file struct {
	After int64            `json:"after"`
	Ops   map[string]Entry `json:"ops"`
}

// Journal is the open journal of one state directory.
type Journal struct {
	mu   sync.Mutex
	path string
	data file
	now  func() time.Time
}

// Open reads the journal in stateDir, or starts an empty one.
func Open(stateDir string, now func() time.Time) (*Journal, error) {
	if now == nil {
		now = time.Now
	}
	j := &Journal{path: filepath.Join(stateDir, FileName), now: now, data: file{Ops: map[string]Entry{}}}
	raw, err := os.ReadFile(j.path)
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return j, nil
	case err != nil:
		return nil, fmt.Errorf("reading the journal: %w", err)
	}
	if err := json.Unmarshal(raw, &j.data); err != nil {
		return nil, fmt.Errorf("%s is not a valid journal: %w", j.path, err)
	}
	if j.data.Ops == nil {
		j.data.Ops = map[string]Entry{}
	}
	j.prune()
	return j, nil
}

// After is the persisted `after` of the long-poll.
func (j *Journal) After() int64 {
	j.mu.Lock()
	defer j.mu.Unlock()
	return j.data.After
}

// Lookup returns the entry of an op, if the journal has one.
func (j *Journal) Lookup(id int64) (Entry, bool) {
	j.mu.Lock()
	defer j.mu.Unlock()
	e, ok := j.data.Ops[key(id)]
	return e, ok
}

// Begin records that the op is about to run. It is persisted before the op runs,
// so a crash in the middle cannot lead to a second run.
func (j *Journal) Begin(op protocol.Op) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.data.Ops[key(op.ID)] = Entry{Sequence: op.Sequence, Op: op.Op, ReceivedAt: j.now().UTC()}
	return j.saveLocked()
}

// Record journals an op that is answered without running, such as an expired one,
// with its result in one write.
func (j *Journal) Record(op protocol.Op, result protocol.Result) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	j.data.Ops[key(op.ID)] = Entry{Sequence: op.Sequence, Op: op.Op, ReceivedAt: j.now().UTC(), Result: &result}
	return j.saveLocked()
}

// Finish records the op's result. It is persisted before the result is posted.
func (j *Journal) Finish(id int64, result protocol.Result) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	e, ok := j.data.Ops[key(id)]
	if !ok {
		return fmt.Errorf("op %d was not begun", id)
	}
	e.Result = &result
	j.data.Ops[key(id)] = e
	return j.saveLocked()
}

// Acknowledge records that the op's result is settled and moves `after` past it.
func (j *Journal) Acknowledge(id int64) error {
	j.mu.Lock()
	defer j.mu.Unlock()
	e, ok := j.data.Ops[key(id)]
	if !ok {
		return fmt.Errorf("op %d was not begun", id)
	}
	e.Accepted = true
	j.data.Ops[key(id)] = e
	if e.Sequence > j.data.After {
		j.data.After = e.Sequence
	}
	return j.saveLocked()
}

// Delete removes the journal file, when the machine is unregistered.
func Delete(stateDir string) error {
	err := os.Remove(filepath.Join(stateDir, FileName))
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	return nil
}

func (j *Journal) saveLocked() error {
	j.prune()
	raw, err := json.Marshal(j.data)
	if err != nil {
		return fmt.Errorf("encoding the journal: %w", err)
	}
	if err := fsutil.WriteFileAtomic(j.path, raw, 0o600); err != nil {
		return fmt.Errorf("writing the journal: %w", err)
	}
	return nil
}

// prune forgets accepted entries received more than Retention ago. An entry whose
// result was never accepted is kept however old it is: the gateway can still
// deliver its op, and only the entry stops a second run.
func (j *Journal) prune() {
	cutoff := j.now().Add(-Retention)
	for k, e := range j.data.Ops {
		if e.Accepted && e.ReceivedAt.Before(cutoff) {
			delete(j.data.Ops, k)
		}
	}
}

func key(id int64) string { return strconv.FormatInt(id, 10) }
