package services

import (
	"fmt"
	"testing"
)

func Test_computeOverRange(t *testing.T) {
	fmt.Println(computeOverRange("darkmatter/stackpanel", 3000, 10000, 100))
	tests := []struct {
		name string // description of this test case
		// Named input parameters for target function.
		key  string
		min  int
		max  int
		mod  int
		want int
	}{
		{
			name: "hello",
			key:  "hello",
			min:  3000,
			max:  10000,
			mod:  100,
			want: 5800,
		},
		{
			name: "darkmatter/stackpanel",
			key:  "darkmatter/stackpanel",
			min:  3000,
			max:  10000,
			mod:  100,
			want: 5700,
		},
		{
			name: "postgres",
			key:  "postgres",
			min:  5700,
			max:  5800,
			mod:  1,
			want: 5756,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeOverRange(tt.key, tt.min, tt.max, tt.mod)
			// TODO: update the condition below to compare got with tt.want.
			if got != tt.want {
				t.Errorf("computeOverRange() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestStablePort(t *testing.T) {
	tests := []struct {
		name string // description of this test case
		// Named input parameters for target function.
		reposlug string
		service  string
		want     int
	}{
		{
			name:     "darkmatter/stackpanel - postgres",
			reposlug: "darkmatter/stackpanel",
			service:  "postgres",
			want:     5756,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := StablePort(tt.reposlug, tt.service)
			if got != tt.want {
				t.Errorf("StablePort() = %v, want %v", got, tt.want)
			}
		})
	}
}
