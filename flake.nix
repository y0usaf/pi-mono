{
  description = "pi monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = forAllSystems (system: import nixpkgs {inherit system;});
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsFor.${system};
      lib = pkgs.lib;
      packageJson = builtins.fromJSON (builtins.readFile ./packages/coding-agent/package.json);

      canvasNativeDeps = with pkgs; [
        cairo
        giflib
        libjpeg
        libpng
        pango
        pixman
      ];
    in {
      pi = pkgs.buildNpmPackage {
        pname = "pi";
        version = packageJson.version;
        src = ./.;
        npmWorkspace = "packages/coding-agent";
        npmBuildScript = "build:binary";

        # Regenerate after dependency changes:
        #   nix build .# 2>&1 | grep 'got:' | awk '{print $2}'
        # or:
        #   nix store prefetch-file --hash-type sha256 --unpack "$(npm pack --json | jq -r '.[0].filename')"
        npmDepsHash = "sha256-dzBmtAhm0X4TsKW9nwKVyhvYlMLphzNtKkDvubWQFPk=";

        nodejs = pkgs.nodejs_22;

        nativeBuildInputs = with pkgs; [bun pkg-config makeWrapper];
        buildInputs = canvasNativeDeps;

        installPhase = ''
          runHook preInstall

          mkdir -p $out/share/pi $out/bin

          # Copy assets (themes, docs, examples, wasm, etc.) but exclude the
          # compiled binary itself to avoid duplicating it in the store.
          cp -R packages/coding-agent/dist/. $out/share/pi/
          rm -f $out/share/pi/pi

          install -Dm755 packages/coding-agent/dist/pi $out/bin/pi
          wrapProgram $out/bin/pi --set PI_PACKAGE_DIR $out/share/pi

          runHook postInstall
        '';

        meta = with lib; {
          description = packageJson.description;
          homepage = "https://shittycodingagent.ai";
          license = licenses.mit;
          mainProgram = "pi";
        };
      };

      default = self.packages.${system}.pi;
    });

    apps = forAllSystems (system: let
      packageJson = builtins.fromJSON (builtins.readFile ./packages/coding-agent/package.json);
    in {
      default = {
        type = "app";
        program = "${self.packages.${system}.pi}/bin/pi";
        meta.description = packageJson.description;
      };
    });

    devShells = forAllSystems (system: let
      pkgs = pkgsFor.${system};

      canvasNativeDeps = with pkgs; [
        cairo
        giflib
        libjpeg
        libpng
        pango
        pixman
      ];
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          # JS toolchain
          nodejs_22
          bun

          # Native build dependencies (canvas)
          pkg-config
        ] ++ canvasNativeDeps;

        shellHook = ''
          echo "pi dev shell — node $(node --version), bun v$(bun --version)"
        '';
      };
    });

    formatter = forAllSystems (system: pkgsFor.${system}.alejandra);
  };
}
