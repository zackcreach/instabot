# Instabot

To start your Phoenix server with a local PostgreSQL server running:

```bash
nix develop
mix setup
iex -S mix phx.server
```

The Nix development shell provides the pinned Erlang, Elixir, Node, PostgreSQL client, Playwright browsers, ImageMagick, and Tesseract tooling on Linux and Darwin.

Without Nix, use [`flake.nix`](flake.nix) as the source of truth for tool versions and install matching Erlang, Elixir, Node, PostgreSQL, Playwright, ImageMagick, and Tesseract tooling with mise, asdf, or equivalent tooling before running `mix setup`.

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Instabot is built as an immutable Nix Mix release and runs as `instabot-native.service` on Symphony. See [the deployment guide](docs/deploy.md) for deployment and operations.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
