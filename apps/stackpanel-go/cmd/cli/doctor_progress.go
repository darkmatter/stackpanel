package cmd

import (
	"fmt"
	"io"
	"sync"
	"time"
)

// Progress goes to stderr, keeping --json stdout machine-readable. Checks may
// finish concurrently; stop waits for the heartbeat before rendering a report.
func startDoctorProgress(out io.Writer) (func(string), func()) {
	var mu sync.Mutex
	progress := func(message string) {
		mu.Lock()
		defer mu.Unlock()
		fmt.Fprintln(out, "Doctor: "+message)
	}
	started := time.Now()
	stop, done := make(chan struct{}), make(chan struct{})
	go func() {
		defer close(done)
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				progress(fmt.Sprintf("still running (%s elapsed; Ctrl+C to cancel)", time.Since(started).Round(time.Second)))
			}
		}
	}()
	var once sync.Once
	return progress, func() { once.Do(func() { close(stop); <-done }) }
}
