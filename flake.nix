{
  inputs = {
    lowrisc-nix.url = "github:lowRISC/lowrisc-nix";
    nixpkgs.follows = "lowrisc-nix/nixpkgs";
    flake-utils.follows = "lowrisc-nix/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    lowrisc-nix,
  }: let
    all_system_outputs = flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
        lowriscPkgs = lowrisc-nix.outputs.packages.${system};
      in {
        formatter = pkgs.alejandra;
        devShells.default = pkgs.mkShellNoCC {
          packages =
            (with pkgs; [
              screen
              dtc
              pkgsCross.riscv64.buildPackages.gcc
            ])
            ++ (with lowriscPkgs; [
              python_ot
              lowrisc-toolchain-gcc-rv64imac
            ]);
        };
      }
    );
  in
    all_system_outputs;
}
