{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs.lib) optionalAttrs optionals;
        beamPackages = pkgs.beamMinimal29Packages.extend (_final: previous: {
          elixir = previous.elixir_1_20;
        });
        version = "0.1.0";
        src = ./.;
        runtimeAssets = pkgs.buildNpmPackage {
          pname = "instabot-runtime-assets";
          inherit version;
          src = ./assets;
          npmDepsHash = "sha256-qw7MJdOgWmX9yz6206HDk/kgjA5urjXrliqkHlBM8a0=";
          npmBuildScript = "bridge:production";
          npmFlags = [ "--ignore-scripts" ];
          preBuild = ''
            npm pkg set scripts.bridge:production="tsc --project tsconfig.playwright.json"
          '';
          postBuild = ''
            npm prune --omit=dev --ignore-scripts
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out/playwright
            cp -r node_modules $out/
            cp -r playwright/dist $out/playwright/
            runHook postInstall
          '';
        };
        mixFodDeps = beamPackages.fetchMixDeps {
          pname = "instabot-mix-deps";
          inherit src version;
          hash = "sha256-tpY7Az5eduy17vcHsLoFREGV5cyMtBiqIVcz2mrm3E8=";
        };
        devPostgres = pkgs.writeShellApplication {
          name = "dev-postgres";
          runtimeInputs = [ pkgs.postgresql_18_jit ];
          text = ''
            root_dir="''${DEV_POSTGRES_ROOT_DIR:-$PWD/.direnv/postgresql-18}"
            data_dir="$root_dir/data"
            socket_dir="$root_dir/socket"

            case "''${1:-}" in
              start)
                mkdir -p "$data_dir" "$socket_dir"
                chmod 700 "$data_dir" "$socket_dir"
                if [[ ! -s "$data_dir/PG_VERSION" ]]; then
                  initdb --pgdata="$data_dir" --username=postgres --auth=trust
                fi
                if pg_ctl --pgdata="$data_dir" status >/dev/null 2>&1; then
                  echo "PostgreSQL is already running"
                else
                  pg_ctl --pgdata="$data_dir" --log="$data_dir/postgresql.log" --options="-c listen_addresses= -c unix_socket_directories='$socket_dir'" start
                fi
                ;;
              stop) pg_ctl --pgdata="$data_dir" stop ;;
              status) pg_ctl --pgdata="$data_dir" status ;;
              *) echo "Usage: dev-postgres start|stop|status" >&2; exit 2 ;;
            esac
          '';
        };
      in
      {
        packages.default = beamPackages.mixRelease {
          pname = "instabot";
          inherit src version mixFodDeps;
          MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
          MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
          postBuild = ''
            mix do deps.loadpaths --no-deps-check + tailwind instabot --minify + esbuild instabot --minify + phx.digest
          '';
          postInstall = ''
            mkdir -p $out/share/instabot
            cp -r ${runtimeAssets} $out/share/instabot/assets
            ln -s ${pkgs.playwright-driver.browsers} $out/share/instabot/playwright-browsers
          '';
        };

        devShells.default = pkgs.mkShell ({
          packages = [
            beamPackages.elixir
            beamPackages.expert
            pkgs.nodejs_24
            pkgs.typescript-language-server
            pkgs.prettier
            pkgs.postgresql_18_jit
            devPostgres
            pkgs.esbuild
            pkgs.tailwindcss_4
            pkgs.pkg-config
            pkgs.imagemagick
            pkgs.tesseract
            pkgs.glibcLocales
          ] ++ optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.chromium
            pkgs.inotify-tools
          ] ++ optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.terminal-notifier
          ];
          MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
          MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = true;
          shellHook = ''
            export LANG="''${LANG:-en_US.UTF-8}"
            export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
            if [[ -z "''${DATABASE_URL:-}" && -z "''${DATABASE_SOCKET_DIR:-}" ]]; then
              export DEV_POSTGRES_ROOT_DIR="$PWD/.direnv/postgresql-18"
              export DATABASE_SOCKET_DIR="$DEV_POSTGRES_ROOT_DIR/socket"
              export DATABASE_USERNAME=postgres
              export PGHOST="$DATABASE_SOCKET_DIR"
              export PGUSER="$DATABASE_USERNAME"
              dev-postgres start
            fi
          '';
        } // optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          INSTABOT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
        });
      }
    );
}
