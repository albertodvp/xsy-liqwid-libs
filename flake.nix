{
  description = "liqwid-plutarch-extra";

  nixConfig = {
    extra-experimental-features = [ "nix-command" "flakes" "ca-derivations" ];
    extra-substituters = [ "https://cache.iog.io" "https://public-plutonomicon.cachix.org" "https://mlabs.cachix.org" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" "public-plutonomicon.cachix.org-1:3AKJMhCLn32gri1drGuaZmFrmnue+KkKrhhubQk/CWc=" ];
    allow-import-from-derivation = "true";
    max-jobs = "auto";
    auto-optimise-store = "true";
  };

  inputs = {
    nixpkgs.follows = "liqwid-nix/nixpkgs";
    nixpkgs-latest.url = "github:NixOS/nixpkgs";

    liqwid-nix = {
      url = "github:Liqwid-Labs/liqwid-nix/v2.2.0";
      inputs.nixpkgs-latest.follows = "nixpkgs-latest";
    };

    plutarch-quickcheck.url = "github:Liqwid-Labs/plutarch-quickcheck";
    plutarch-context-builder.url = "github:Liqwid-Labs/plutarch-context-builder";

    ply.url = "github:mlabs-haskell/ply?ref=master";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.liqwid-nix.flakeModule
      ];
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" "aarch64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          pkgs = import inputs.nixpkgs-latest { inherit system; };
        in
        {
          onchain.default = {
            src = ./.;
            ghc.version = "ghc925";
            fourmolu.package = pkgs.haskell.packages.ghc943.fourmolu_0_10_1_0;
            hlint = { };
            cabalFmt = { };
            hasktags = { };
            applyRefact = { };
            shell = { };
            enableBuildChecks = true;
            extraHackageDeps = [
              "${inputs.plutarch-context-builder}"
              "${inputs.plutarch-quickcheck}"
              "${inputs.ply}/ply-core"
              "${inputs.ply}/ply-plutarch"
            ];
          };
          ci.required = [ "all_onchain" ];
        };
    };
}
