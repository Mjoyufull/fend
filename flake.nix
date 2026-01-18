{
  description = "fend - Fast file finder with frecency-based history";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, zig-overlay, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
          zig = pkgs.zig;
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "fend";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ zig ];
            buildPhase = ''
              ${zig}/bin/zig build -Doptimize=ReleaseSafe
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp zig-out/bin/fend $out/bin/fend
            '';
          };
        }
      );

      defaultPackage = forAllSystems (system: self.packages.${system}.default);

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/fend";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [ pkgs.zig ];
            shellHook = ''
              echo "fend development shell"
              echo "Run 'zig build' to build the project"
            '';
          };
        }
      );
    };
}
