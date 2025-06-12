{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      lib = nixpkgs.lib;
      fs = lib.fileset;
    in
    {

      packages.x86_64-linux = rec {
        nginxSource2 =
          let
            nginx = pkgs.nginx;
          in
          # Works with override {modules = []}
          (nginx.override{}).overrideAttrs (
            finalAttrs: previousAttrs: {
              outputs = previousAttrs.outputs ++ [
                # "objs"
                "source"
              ];
              disallowedReferences = [];

              postInstall = let

                  noSourceRefs = lib.concatMapStrings (
                    m: "remove-references-to -t ${m.src} $(readlink -fn $sources/obj/Makefile)\n"
                  ) previousAttrs.passthru.modules;

              in previousAttrs.postInstall + ''
                  mkdir -p $source/
                  cp -r * $source/

                  # Clear objs
                  rm -rf $source/objs
                  mkdir -p $source/objs

                  # Repopulate with required files
                  grep -v '#define NGX_CONFIGURE' objs/ngx_auto_config.h > $source/objs/ngx_auto_config.h
                  cp objs/ngx_auto_headers.h $source/objs/ngx_auto_headers.h

                  sed -n '/^ALL_INCS *=/,/[^\\]$/p' objs/Makefile > $source/objs/Makefile
                  cp objs/Makefile $source/objs/Makefile
              '';
            }
          );
        nginxSource =
          let
            nginx = pkgs.nginx;
          in
          (nginx.override{modules = [];}).overrideAttrs (
            finalAttrs: previousAttrs: {
              outputs = [
                # "objs"
                "out"
              ];

              # postUnpack = ''
              #   mkdir -p $out/
              #   cp -r * $out/
              # '';
              # Skip all phases except unpack
              dontBuild = true;
              # dontConfigure = true;
              dontInstall = true;
              doInstallCheck = false;

              postFixup =
                (previousAttrs.postFixup or "")
                + ''
                  mkdir -p $out/
                  cp -r * $out/
                '';

             postInstall =  (previousAttrs.postInstall or "") +
                (let
                  noSourceRefs = lib.concatMapStrings (
                    m: "remove-references-to -t ${m.src} $(readlink -fn $sources/obj/Makefile)\n"
                  ) previousAttrs.passthru.modules;
                in
                noSourceRefs);

                
            }
          );
        # pkgs.stdenv.mkDerivation {
        #   name = "${nginx.name}-source";
        #   version = nginx.version;
        #   src = nginx.src;

        #   outputs = [
        #     "src"
        #     "objs"
        #   ];

        #   # Skip all phases except unpack
        #   # dontBuild = true;
        #   # dontConfigure = true;
        #   # dontInstall = true;

        #   preBuild = ''
        #     mkdir -p $src/
        #   '';

        #   postFixup = ''
        #     mkdir -p $objs
        #     cp -r objs $objs/
        #   '';

        # };
        #

        default = pkgs.rustPlatform.buildRustPackage (
          final:
          let
            cargoTOML = lib.importTOML "${final.src}/Cargo.toml";

          in
          {
            pname = cargoTOML.package.name;
            inherit (cargoTOML.package) version;

            src = fs.toSource {
              root = ./.;
              fileset = fs.intersection (fs.gitTracked ./.) (
                fs.unions [
                  ./Cargo.lock
                  ./Cargo.toml
                  ./src
                ]
              );
            };

            buildInputs = nginxSource.buildInputs;
            nativeBuildInputs = [
              pkgs.rustPlatform.bindgenHook
            ];



            cargoLock = {
              lockFile = ./Cargo.lock;
              outputHashes = {
                "nginx-sys-0.5.0" = "sha256-dnBybf59K8dFq3zLxty1D9vseDN4pToT1QzWRPNgqaw=";
              };
            };

            preBuild = ''
              # mkdir -p objs
              # NGINX_BUILD_DIR=$(realpath objs)
              # export NGINX_BUILD_DIR

            '';

            env = {
              "NGINX_SOURCE_DIR" = nginxSource2.source;
            };

          }
        );
      };
    };
}
