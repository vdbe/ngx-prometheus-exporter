{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # We want to generate outputs for as many systems as possible,
      # even if we don't officially support or test for them
      allSystems = lib.systems.flakeExposed;

      # These are the systems we do officially support and test, though
      supportedSystems = [
        "x86_64-linux"
        # "aarch64-linux"
        "x86_64-darwin"
        # "aarch64-darwin"
      ];

      forAllSystems = lib.genAttrs allSystems;
      nixpkgsFor = nixpkgs.legacyPackages;
    in
    {
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          packages = self.packages.${system};

          mkCheck =
            name: deps: script:
            pkgs.runCommand name { nativeBuildInputs = deps; } ''
              ${script}
              touch $out
            '';
        in
        lib.optionalAttrs (lib.elem system supportedSystems) {
          package_sshd-command = packages.default;

          clippy = (packages.default.override { lto = false; }).overrideAttrs {
            pname = "check-clippy";

            nativeBuildInputs = [
              pkgs.cargo
              pkgs.clippy
              pkgs.clippy-sarif
              pkgs.rustPlatform.cargoSetupHook
              pkgs.rustPlatform.bindgenHook
              pkgs.rustc
              pkgs.sarif-fmt
            ];

            buildPhase = ''
              runHook preBuild
              cargo clippy \
                --all-features \
                --all-targets \
                --tests \
                --message-format=json \
              | clippy-sarif | tee $out | sarif-fmt
              runHook postBuild
            '';

            dontInstall = true;
            doCheck = false;
            doInstallCheck = false;
            dontFixup = true;

            passthru = { };
            meta = { };
          };

          rustfmt = mkCheck "check-cargo-fmt" [
            pkgs.cargo
            pkgs.rustfmt
          ] "cd ${self} && cargo fmt -- --check";

          # actionlint = mkCheck "check-actionlint" [
          #   pkgs.actionlint
          # ] "actionlint ${self}/.github/workflows/*";

          # zizmor = mkCheck "check-zizmor" [
          #   pkgs.zizmor
          # ] "zizmor --pedantic ${self}";

          typos = mkCheck "check-typos" [ pkgs.typos ] "typos --hidden ${self}";

          deadnix = mkCheck "check-deadnix" [ pkgs.deadnix ] "deadnix --fail ${self}";

          nixfmt = mkCheck "check-nixfmt" [ pkgs.nixfmt-rfc-style ] "nixfmt --check ${self}";

          statix = mkCheck "check-statix" [ pkgs.statix ] "statix check ${self}";
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        lib.optionalAttrs (lib.elem system supportedSystems) {
          default = pkgs.mkShell {
            packages = [
              # Rust tools
              pkgs.clippy
              pkgs.clippy-sarif
              pkgs.sarif-fmt
              pkgs.rust-analyzer
              pkgs.rustfmt

              # Nix tools
              self.formatter.${system}
              pkgs.nixd
              pkgs.statix

              # Github action tools
              pkgs.efm-langserver
              pkgs.yaml-language-server
              pkgs.actionlint
            ];

            env = {
              RUST_SRC_PATH = toString pkgs.rustPlatform.rustLibSrc;
              NGINX_SOURCE_DIR = self.packages.${system}.default.passthru.nginxSource.out;
            };

            inputsFrom = [ self.packages.${system}.default ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgsFor.${system}.nixfmt-rfc-style);

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          pkgs' = import ./default.nix { inherit pkgs; };
        in
        pkgs'
        // {
          default = pkgs'.ngx-prometheus-exporter;
        }
      );

      # packages.x86_64-linux = rec {
      #   nginxSource4 =
      #     let
      #       nginx = pkgs.nginx;
      #     in
      #     # Works with override {modules = []}
      #     nginx.overrideAttrs (
      #       finalAttrs: previousAttrs: {
      #         pname = "${previousAttrs.pname}-source";
      #         outputs = [ "out" ];

      #         dontBuild = true;
      #         dontInstall = true;
      #         # NOTE: Think I can skip configure if I manually set ALL_INCS in the make file
      #         # dontConfigure = true;

      #         postPatch =
      #           (previousAttrs.postPatch or "")
      #           + ''
      #             mkdir -p $out
      #             cp -r * $out
      #           '';

      #         postFixup = ''
      #           # Populate objs with required files
      #           mkdir -p $out/objs

      #           grep -v '#define NGX_CONFIGURE' objs/ngx_auto_config.h > $out/objs/ngx_auto_config.h
      #           cp objs/ngx_auto_headers.h $out/objs/ngx_auto_headers.h

      #           sed -n '/^ALL_INCS *=/,/[^\\]$/p' objs/Makefile | grep -v "/nix/store" > $out/objs/Makefile
      #         '';

      #       }
      #     );
      #   nginxSource3 =
      #     let
      #       nginx = pkgs.nginx;
      #     in
      #     pkgs.stdenv.mkDerivation {
      #       name = "${nginx.name}-source";
      #       version = nginx.version;
      #       src = nginx.src;

      #       buildInputs = nginx.buildInputs;

      #       dontBuild = true;
      #       dontInstall = true;
      #       # NOTE: Think I can skip configure if I manually set ALL_INCS in the make file
      #       # dontConfigure = true;

      #       postFixup = ''
      #         mkdir -p $out
      #         cp -r * $out
      #         mkdir -p $out/objs

      #         # Populate objs with required files
      #         grep -v '#define NGX_CONFIGURE' objs/ngx_auto_config.h > $out/objs/ngx_auto_config.h
      #         cp objs/ngx_auto_headers.h $out/objs/ngx_auto_headers.h

      #         sed -n '/^ALL_INCS *=/,/[^\\]$/p' objs/Makefile | grep -v "/nix/store" > $out/objs/Makefile
      #       '';
      #     };
      #   nginxSource2 =
      #     let
      #       nginx = pkgs.nginx;
      #     in
      #     # Works with override {modules = []}
      #     (nginx.override { }).overrideAttrs (
      #       finalAttrs: previousAttrs: {
      #         outputs = previousAttrs.outputs ++ [
      #           "source"
      #         ];
      #         disallowedReferences = [ ];

      #         postInstall =
      #           let

      #             noSourceRefs = lib.concatMapStrings (
      #               m: "remove-references-to -t ${m.src} $(readlink -fn $sources/obj/Makefile)\n"
      #             ) previousAttrs.passthru.modules;

      #           in
      #           previousAttrs.postInstall
      #           + ''
      #             mkdir -p $source/
      #             cp -r * $source/

      #             # Clear objs
      #             rm -rf $source/objs
      #             mkdir -p $source/objs

      #             # Repopulate with required files
      #             grep -v '#define NGX_CONFIGURE' objs/ngx_auto_config.h > $source/objs/ngx_auto_config.h
      #             cp objs/ngx_auto_headers.h $source/objs/ngx_auto_headers.h

      #             sed -n '/^ALL_INCS *=/,/[^\\]$/p' objs/Makefile > $source/objs/Makefile
      #             cp objs/Makefile $source/objs/Makefile
      #           '';
      #       }
      #     );
      #   nginxSource =
      #     let
      #       nginx = pkgs.nginx;
      #     in
      #     (nginx.override { modules = [ ]; }).overrideAttrs (
      #       finalAttrs: previousAttrs: {
      #         outputs = [
      #           # "objs"
      #           "out"
      #         ];

      #         # postUnpack = ''
      #         #   mkdir -p $out/
      #         #   cp -r * $out/
      #         # '';
      #         # Skip all phases except unpack
      #         dontBuild = true;
      #         # dontConfigure = true;
      #         dontInstall = true;
      #         doInstallCheck = false;

      #         postFixup =
      #           (previousAttrs.postFixup or "")
      #           + ''
      #             mkdir -p $out/
      #             cp -r * $out/
      #           '';

      #         postInstall =
      #           (previousAttrs.postInstall or "")
      #           + (
      #             let
      #               noSourceRefs = lib.concatMapStrings (
      #                 m: "remove-references-to -t ${m.src} $(readlink -fn $sources/obj/Makefile)\n"
      #               ) previousAttrs.passthru.modules;
      #             in
      #             noSourceRefs
      #           );
      #       }
      #     );
      #   # pkgs.stdenv.mkDerivation {
      #   #   name = "${nginx.name}-source";
      #   #   version = nginx.version;
      #   #   src = nginx.src;

      #   #   outputs = [
      #   #     "src"
      #   #     "objs"
      #   #   ];

      #   #   # Skip all phases except unpack
      #   #   # dontBuild = true;
      #   #   # dontConfigure = true;
      #   #   # dontInstall = true;

      #   #   preBuild = ''
      #   #     mkdir -p $src/
      #   #   '';

      #   #   postFixup = ''
      #   #     mkdir -p $objs
      #   #     cp -r objs $objs/
      #   #   '';

      #   # };
      #   #

      #   default = pkgs.rustPlatform.buildRustPackage (
      #     final:
      #     let
      #       cargoTOML = lib.importTOML "${final.src}/Cargo.toml";

      #     in
      #     {
      #       pname = cargoTOML.package.name;
      #       inherit (cargoTOML.package) version;

      #       src = fs.toSource {
      #         root = ./.;
      #         fileset = fs.intersection (fs.gitTracked ./.) (
      #           fs.unions [
      #             ./Cargo.lock
      #             ./Cargo.toml
      #             ./src
      #           ]
      #         );
      #       };

      #       buildInputs = nginxSource.buildInputs;
      #       nativeBuildInputs = [
      #         pkgs.rustPlatform.bindgenHook
      #       ];

      #       cargoLock = {
      #         lockFile = ./Cargo.lock;
      #         outputHashes = {
      #           "nginx-sys-0.5.0" = "sha256-dnBybf59K8dFq3zLxty1D9vseDN4pToT1QzWRPNgqaw=";
      #         };
      #       };

      #       preBuild = ''
      #         # mkdir -p objs
      #         # NGINX_BUILD_DIR=$(realpath objs)
      #         # export NGINX_BUILD_DIR

      #       '';

      #       env = {
      #         "NGINX_SOURCE_DIR" = nginxSource4.out;
      #       };

      #     }
      #   );
      # };
    };
}
