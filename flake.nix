{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      deploy-rs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        beamPackages = pkgs.beamMinimal27Packages.extend (
          _final: previous: {
            elixir = previous.elixir_1_20;
          }
        );
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
          runtimeInputs = [ pkgs.postgresql_18 ];
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
                  pg_ctl --pgdata="$data_dir" --log="$data_dir/postgresql.log" \
                    --options="-c listen_addresses= -c unix_socket_directories='$socket_dir'" start
                fi
                ;;
              stop)
                pg_ctl --pgdata="$data_dir" stop
                ;;
              status)
                pg_ctl --pgdata="$data_dir" status
                ;;
              *)
                echo "Usage: dev-postgres start|stop|status" >&2
                exit 2
                ;;
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
            mkdir -p $out/share/prominent-tools
            printf '%s\n' '${self.rev or self.dirtyRev or "0000000000000000000000000000000000000000"}' > $out/share/prominent-tools/revision
          '';
        };

        packages.deploy-rs = deploy-rs.packages.${system}.default;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            beamPackages.elixir
            pkg-config
            imagemagick
            nodejs
            playwright-driver.browsers
            postgresql_18
            devPostgres
            esbuild
            tailwindcss_4
            tesseract
          ];

          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = true;
          MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
          MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";

          shellHook = ''
            export LANG="''${LANG:-en_US.UTF-8}"
            export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
            if [[ -z "''${DATABASE_URL:-}" && -z "''${DATABASE_SOCKET_DIR:-}" ]]; then
              export DEV_POSTGRES_ROOT_DIR="$PWD/.direnv/postgresql-18"
              export DATABASE_SOCKET_DIR="$DEV_POSTGRES_ROOT_DIR/socket"
              export DATABASE_USERNAME="postgres"
              export PGHOST="$DATABASE_SOCKET_DIR"
              export PGUSER="$DATABASE_USERNAME"
              dev-postgres start
            fi
          '';
        };

        devShell = self.devShells.${system}.default;
      }
    )
    // {
      deploy.nodes.symphony = {
        hostname = "symphony";
        sshUser = "prominent-deploy";
        sshOpts = [
          "-o"
          "StrictHostKeyChecking=accept-new"
        ];
        remoteBuild = true;
        profiles.instabot = {
          user = "prominent-deploy";
          profilePath = "/nix/var/nix/profiles/per-user/prominent-deploy/instabot";
          path = deploy-rs.lib.x86_64-linux.activate.custom self.packages.x86_64-linux.default "sudo /run/current-system/sw/bin/prominent-tools-activate instabot";
        };
      };

      checks.x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks self.deploy;
    };
}
