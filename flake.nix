# First draft of this flake include a large amount of cruft to be compatible
# with both pre and post Nix 2.6 APIs.
#
# The expected state is to support bundlers of the form:
# bundlers.<system>.<name> = drv: some-drv;

{
  description = "Example bundlers";

  inputs.nix-utils.url = "github:juliosueiras-nix/nix-utils";
  inputs.nix-utils.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-bundle.url = "github:matthewbauer/nix-bundle";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/22.05";

  outputs = { self, nixpkgs, nix-bundle, nix-utils }: let
      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # Backwards compatibility helper for pre Nix2.6 bundler API
      program = p: with builtins; with p; "${outPath}/bin/${
        if p?meta && p.meta?mainProgram then
          meta.mainProgram
          else (parseDrvName (unsafeDiscardStringContext p.name)).name
      }";
  in {
    defaultBundler = builtins.listToAttrs (map (system: {
        name = system;
        value = drv: self.bundlers.${system}.default drv;
      }) supportedSystems);

    bundlers =
      (forAllSystems (system: rec {

      default = toArx;
      toArx = drv: nix-bundle.bundlers.nix-bundle {inherit system; program=program drv;};

      toRPM = drv: nix-utils.bundlers.rpm {inherit system; program=program drv;};

      toDEB = drv: nix-utils.bundlers.deb {inherit system; program=program drv;};

      toDockerImage = {...}@drv:
        (nixpkgs.legacyPackages.${system}.dockerTools.buildLayeredImage {
          name = drv.name;
          tag = "latest";
          contents = [ drv ];
      });

      toBuildDerivation = drv:
        (import ./report/default.nix {
          inherit drv;
          pkgs = nixpkgsFor.${system};}).buildtimeDerivations;

      toReport = drv:
        (import ./report/default.nix {
          inherit drv;
          pkgs = nixpkgsFor.${system};}).runtimeReport;

      identity = drv: drv;
    }
    ));
  };
}
