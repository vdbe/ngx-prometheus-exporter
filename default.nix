{
  pkgs ? import nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  },
  lib ? pkgs.lib,
  nixpkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
}:

let
  callPackage = lib.callPackageWith (pkgs // pkgs');

  pkgs' = {
    ngx-prometheus-exporter = callPackage ./nix/package.nix { };
  };
in
pkgs'
