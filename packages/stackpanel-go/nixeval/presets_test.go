package nixeval_test

import (
	"context"
	"testing"

	"github.com/darkmatter/stackpanel/packages/stackpanel-go/nixeval"
)

func TestEvalExpr(t *testing.T) {
	tests := []struct {
		name string // description of this test case
		// Named input parameters for target function.
		nixExpr string
		want    *nixeval.EvalExprResult
		wantErr bool
	}{
		// TODO: Add test cases.
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, gotErr := nixeval.EvalExpr(context.Background(), tt.nixExpr)
			if gotErr != nil {
				if !tt.wantErr {
					t.Errorf("EvalExpr() failed: %v", gotErr)
				}
				return
			}
			if tt.wantErr {
				t.Fatal("EvalExpr() succeeded unexpectedly")
			}
			// TODO: update the condition below to compare got with tt.want.
			if true {
				t.Errorf("EvalExpr() = %v, want %v", got, tt.want)
			}
		})
	}
}
