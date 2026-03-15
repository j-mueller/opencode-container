{
  description = "Opencode container";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    n2c = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, n2c }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f system (import nixpkgs { inherit system; }));

      mkDevShellPackages = pkgs:
        with pkgs; [
          dhall
          python3
          sshpass
          sqlcmd
          jq
        ];
    in
    {
      devShells = forAllSystems (_system: pkgs: {
        default = pkgs.mkShell {
          packages = mkDevShellPackages pkgs;
        };
      });

      packages = forAllSystems (system: pkgs:
        let
          lib = pkgs.lib;
          devShellPackages = mkDevShellPackages pkgs;
          unstablePkgs = import nixpkgs-unstable { inherit system; };
          opencodeAi = import ./nix/opencode-ai.nix {
            inherit pkgs system;
          };
        in
        lib.optionalAttrs pkgs.stdenv.isLinux (
          let
            dockerImage = import ./nix/opencode-image.nix {
              inherit pkgs n2c devShellPackages opencodeAi;
              nixPackage = unstablePkgs.nixVersions.nix_2_33;
            };
            runDockerImage = import ./nix/run-opencode.nix {
              inherit pkgs dockerImage;
            };
          in
          rec {
            inherit dockerImage runDockerImage;

            default = dockerImage;
          }
        ));

      apps = forAllSystems (system: pkgs:
        let
          lib = pkgs.lib;
          devShellPackages = mkDevShellPackages pkgs;
          unstablePkgs = import nixpkgs-unstable { inherit system; };
          opencodeAi = import ./nix/opencode-ai.nix {
            inherit pkgs system;
          };
        in
        lib.optionalAttrs pkgs.stdenv.isLinux (
          let
            dockerImage = import ./nix/opencode-image.nix {
              inherit pkgs n2c devShellPackages opencodeAi;
              nixPackage = unstablePkgs.nixVersions.nix_2_33;
            };
            runDockerImagePkg = import ./nix/run-opencode.nix {
              inherit pkgs dockerImage;
            };
          in
          rec {
            runDockerImage = {
              type = "app";
              program = "${runDockerImagePkg}/bin/run-opencode-container";
            };

            default = runDockerImage;
          }
        ));
    };
}
