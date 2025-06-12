{
  lib,
  rustPlatform,

  nginx,

  lto ? true,
}:
let
  fs = lib.fileset;

  nginxSource = nginx.overrideAttrs (previousAttrs: {
    pname = "${previousAttrs.pname}-source";
    outputs = [ "out" ];

    dontBuild = true;
    dontInstall = true;
    # NOTE: Think I can skip configure if I manually set ALL_INCS in the make file
    # dontConfigure = true;

    postPatch =
      (previousAttrs.postPatch or "")
      + ''
        mkdir -p $out
        cp -r * $out
      '';

    postFixup =
      (previousAttrs.postFixup or "")
      + ''
        # Populate objs with required files
        mkdir -p $out/objs

        grep -v '#define NGX_CONFIGURE' objs/ngx_auto_config.h > $out/objs/ngx_auto_config.h
        cp objs/ngx_auto_headers.h $out/objs/ngx_auto_headers.h

        sed -n '/^ALL_INCS *=/,/[^\\]$/p' objs/Makefile | grep -v "/nix/store" > $out/objs/Makefile
      '';

  });

in
rustPlatform.buildRustPackage (
  final:
  let
    cargoTOML = lib.importTOML "${final.src}/Cargo.toml";
  in
  {
    pname = cargoTOML.package.name;
    inherit (cargoTOML.package) version;

    src = fs.toSource {
      root = ../.;
      fileset = fs.intersection (fs.gitTracked ../.) (
        fs.unions [
          ../Cargo.lock
          ../Cargo.toml
          ../src

          ../rustfmt.toml
        ]
      );
    };

    cargoLock = {
      lockFile = "${final.src}/Cargo.lock";
      outputHashes = {
        "nginx-sys-0.5.0" = "sha256-dnBybf59K8dFq3zLxty1D9vseDN4pToT1QzWRPNgqaw=";
      };
    };

    inherit (nginxSource) buildInputs;
    nativeBuildInputs = [
      rustPlatform.bindgenHook
    ];

    env =
      let
        rustFlags = lib.optionalAttrs lto {
          lto = "yes";
          strip = "symbols";
          embed-bitcode = "yes";
        };
      in
      {
        RUSTFLAGS = toString (lib.mapAttrsToList (name: value: "-C ${name}=${toString value}") rustFlags);
        NGINX_SOURCE_DIR = nginxSource.out;
      };

    passthru = {
      inherit cargoTOML nginxSource;
    };
  }
)
