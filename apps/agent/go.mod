module github.com/darkmatter/stackpanel/agent

go 1.22

require (
	github.com/darkmatter/stackpanel/packages/stackpanel-go v0.0.0
	github.com/gorilla/websocket v1.5.3
	github.com/rs/zerolog v1.33.0
	gopkg.in/yaml.v3 v3.0.1
)

replace github.com/darkmatter/stackpanel/packages/stackpanel-go => ../../packages/stackpanel-go

require (
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	golang.org/x/sys v0.28.0 // indirect
)
