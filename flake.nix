{
  description = "pi monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
      lib = pkgs.lib;
      packageJson = builtins.fromJSON (builtins.readFile ./packages/coding-agent/package.json);
    in {
      packages.pi = pkgs.buildNpmPackage {
        pname = "pi";
        version = packageJson.version;
        src = ./.;
        npmWorkspace = "packages/coding-agent";
        npmBuildScript = "build:binary";
        npmDepsHash = "sha256-dzBmtAhm0X4TsKW9nwKVyhvYlMLphzNtKkDvubWQFPk=";
        nodejs = pkgs.nodejs_20;
        nativeBuildInputs = [pkgs.bun pkgs.pkg-config pkgs.makeWrapper];
        buildInputs = [
          pkgs.cairo
          pkgs.giflib
          pkgs.libjpeg
          pkgs.libpng
          pkgs.pango
          pkgs.pixman
        ];
        installPhase = ''
          runHook preInstall
          mkdir -p $out/share/pi
          cp -R packages/coding-agent/dist/. $out/share/pi/
          install -Dm755 packages/coding-agent/dist/pi $out/bin/pi
          wrapProgram $out/bin/pi --set PI_PACKAGE_DIR $out/share/pi
          runHook postInstall
        '';
        meta = with lib; {
          description = packageJson.description;
          homepage = "https://shittycodingagent.ai";
          license = licenses.mit;
          mainProgram = "pi";
          platforms = platforms.linux;
        };
      };

      packages.default = self.packages.${system}.pi;

      apps.default = flake-utils.lib.mkApp {
        drv = self.packages.${system}.pi;
      };

      formatter = pkgs.alejandra;
    });
}
