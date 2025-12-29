package services

import "testing"

func TestRegistryLifecycle(t *testing.T) {
	reg := NewRegistry()
	mock := &mockService{name: "demo"}
	reg.Register(mock)

	if !reg.Has("demo") {
		t.Fatalf("expected registry to have demo")
	}
	if reg.Get("demo") == nil {
		t.Fatalf("expected to retrieve demo service")
	}
	if len(reg.Names()) != 1 || reg.Names()[0] != "demo" {
		t.Fatalf("unexpected names: %v", reg.Names())
	}
}

type mockService struct {
	name string
}

func (m *mockService) Name() string                  { return m.name }
func (m *mockService) DisplayName() string           { return m.name }
func (m *mockService) Aliases() []string             { return nil }
func (m *mockService) Port() int                     { return 0 }
func (m *mockService) DataDir() string               { return "" }
func (m *mockService) PidFile() string               { return "" }
func (m *mockService) LogFile() string               { return "" }
func (m *mockService) Start() error                  { return nil }
func (m *mockService) Stop() error                   { return nil }
func (m *mockService) Status() ServiceStatus         { return ServiceStatus{} }
func (m *mockService) StatusInfo() map[string]string { return nil }
