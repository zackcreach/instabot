# Symphony Deployment

Instabot is an immutable Nix Mix release managed by `instabot-native.service`. Nix packages its Node bridge and matching Chromium runtime. Uploads and screenshots live under `/var/lib/instabot`, and the application connects to NixOS-managed PostgreSQL 18.4 through `/run/postgresql`.

## Deploy

Push the application commit, then update and activate its pinned input from `/etc/nixos`:

```bash
nix flake update instabot
nix build .#nixosConfigurations.symphony.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#symphony
```

The systemd dependency runs `instabot-native-migrate.service` before the application starts.

## Operations

```bash
systemctl status instabot-native
journalctl -u instabot-native --follow
sudo systemctl restart instabot-native
curl --fail https://instabot.prominent.tools/health
```

## Database and backups

```bash
sudo -u postgres psql instabot_prod
systemctl status postgresqlBackup-instabot_prod.timer
sudo systemctl start postgresqlBackup-instabot_prod.service
journalctl -u postgresqlBackup-instabot_prod.service
```

Backups are compressed SQL dumps under `/var/backup/postgresql/symphony` on Biltmore. Restore tests must use an isolated database.

## State and rollback

Systemd owns `/var/lib/instabot/uploads` and `/var/lib/instabot/screenshots`. Use the previous NixOS generation for an application rollback. Pre-cutover Docker database and media volumes remain available only during the temporary migration rollback window.
