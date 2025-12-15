# network/

Internal network infrastructure - Tailscale, DNS, and certificates.

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Module entrypoint |
| `tailscale.nix` | Tailscale configuration |

## Planned Options

```nix
stackpanel.network = {
  enable = true;

  tailscale = {
    enable = true;
    authKeySecret = "TAILSCALE_AUTH_KEY";
  };

  dns = {
    enable = true;
    domain = "internal.acme.com";
    provider = "coredns";  # or "caddy"
  };

  certificates = {
    enable = true;
    ca = "step";  # smallstep CA
  };
};
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Tailscale Network                   │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ Dev Mac │  │ Server  │  │ CI      │         │
│  └────┬────┘  └────┬────┘  └────┬────┘         │
│       │            │            │               │
│       └────────────┼────────────┘               │
│                    │                            │
│            ┌───────▼───────┐                    │
│            │   DNS/CA      │                    │
│            │   Server      │                    │
│            └───────────────┘                    │
└─────────────────────────────────────────────────┘
```

## TODO

- [ ] Tailscale auth key management
- [ ] DNS server setup (CoreDNS or Caddy)
- [ ] Step-CA for internal certificates
- [ ] Auto-register services in DNS
- [ ] mTLS between services
