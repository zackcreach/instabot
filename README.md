# Instabot

## Development

```bash
nix develop -c mix setup
nix develop -c iex -S mix phx.server
```

The Nix shell starts a checkout-private PostgreSQL 18 server under `.direnv/postgresql-18` and supplies Chromium to Playwright without a browser download. Use `PORT=<port> nix develop -c iex -S mix phx.server` for another session. `nix develop -c dev-postgres status` and `nix develop -c dev-postgres stop` provide lifecycle control. `DATABASE_URL` or `DATABASE_SOCKET_DIR` uses an external database instead.

Docker Compose is for container and release verification, not normal local development.
