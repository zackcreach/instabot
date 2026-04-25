# Instabot Deployment

Instabot deploys to Symphony with the same Docker plus NixOS pattern used by Whiteboard and Quench.

## Runtime

- App: `instabot`
- Database: `instabot_db`
- Port: `4002`
- Health check: `http://symphony:4002/health`
- Repo path on Symphony: `/home/zack/dev/instabot`
- Env file on Symphony: `/etc/instabot/env`

## Required Environment

Create `/etc/instabot/env` on Symphony:

```sh
SECRET_KEY_BASE=<mix phx.gen.secret>
MAILGUN_API_KEY=<mailgun-api-key>
MAILGUN_DOMAIN=<mailgun-domain>
MAILGUN_FROM_EMAIL=<from-address>
GITHUB_TOKEN=<github-token>
```

The NixOS services load this file with `EnvironmentFile`. `docker-compose.yml` provides the default production `DATABASE_URL`, `PORT`, `PHX_HOST`, scraper bridge path, uploads path, screenshots path, and Playwright browser path.

## First Deploy

```sh
cd /home/zack/dev/nixos
sudo nixos-rebuild switch --flake .#symphony

sudo mkdir -p /etc/instabot
sudo nano /etc/instabot/env

cd /home/zack/dev
git clone <instabot-repo-url> instabot

sudo systemctl start instabot
sudo systemctl start instabot-deploy
curl http://symphony:4002/health
```

## Manual Operations

```sh
mix deploy
mix deploy --force
docker compose ps
docker compose logs instabot -f
docker exec -it instabot /app/bin/instabot remote
docker exec -it instabot_db psql -U postgres -d instabot_prod
sudo systemctl start instabot-backup
```
