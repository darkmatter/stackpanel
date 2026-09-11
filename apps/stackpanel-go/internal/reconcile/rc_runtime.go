package reconcile

import (
	"fmt"
	"net"
	"net/http"
	"path/filepath"
	"strconv"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/internal/setupsession"
	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/services"
)

type RuntimeReconciler struct{ SessionID string }

func (r *RuntimeReconciler) ID() string                           { return "runtime" }
func (r *RuntimeReconciler) Apply(*Context) (*ApplyResult, error) { return &ApplyResult{}, nil }
func (r *RuntimeReconciler) Diagnose(ctx *Context) (*Diagnosis, error) {
	s, err := setupsession.Load(r.SessionID)
	if err != nil {
		return nil, err
	}
	root, err := filepath.EvalSymlinks(ctx.ProjectRoot)
	if err != nil {
		return nil, err
	}
	if root != s.Root {
		return nil, fmt.Errorf("setup session belongs to another repository")
	}
	d := &Diagnosis{}
	check := func(id string, err error) {
		c := CheckResult{ID: id, Module: "onboarding", Scope: "runtime", Status: "pass"}
		if err != nil {
			c.Status = "fail"
			c.Message = err.Error()
		}
		d.CheckResults = append(d.CheckResults, c)
	}
	health, err := setupsession.ReadHealth(&http.Client{Timeout: 2 * time.Second}, s.Endpoint)
	if err == nil && (health.AgentID != s.AgentID || health.SetupVersion < 1 || filepath.Clean(health.ProjectRoot) != root || !health.DevshellReady) {
		err = fmt.Errorf("agent identity changed or agent lacks setup support")
	}
	check("agent-ready", err)
	services.InitForProject(ctx.ProjectRoot)
	for _, name := range s.Services {
		var serviceErr error
		service := services.Get(name)
		if service == nil {
			serviceErr = fmt.Errorf("unknown service %s", name)
		} else if !service.Status().Running {
			serviceErr = fmt.Errorf("service is stopped")
		} else {
			conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(service.Port())), time.Second)
			serviceErr = err
			if conn != nil {
				conn.Close()
			}
		}
		check("service:"+name, serviceErr)
	}
	if s.RequireBrowser {
		var browserErr error
		if s.ReadyAt.IsZero() || time.Since(s.ReadyAt) > time.Minute || s.Connection == "" || time.Since(s.ConnectedAt) > 15*time.Second {
			browserErr = fmt.Errorf("Studio has not confirmed this repository with a live authenticated connection")
		}
		check("studio-ready", browserErr)
	}
	return d, nil
}
