{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        beamPackages = pkgs.beamMinimal27Packages.extend (
          _final: previous: {
            elixir = previous.elixir_1_19;
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
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            beamPackages.elixir
            pkg-config
            imagemagick
            nodejs
            playwright-driver.browsers
            postgresql_18
            tesseract
          ];

          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = true;

          shellHook = ''
            export LANG="''${LANG:-en_US.UTF-8}"
            export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
          '';
        };

        devShell = self.devShells.${system}.default;
      }
    );
}
