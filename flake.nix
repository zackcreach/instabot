{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            pkg-config
            tesseract
          ];

          shellHook = ''
            export LANG="''${LANG:-en_US.UTF-8}"
            export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
          '';
        };

        devShell = self.devShells.${system}.default;
      }
    );
}
