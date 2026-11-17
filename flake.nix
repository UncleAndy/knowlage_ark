{
  description = "KOVCHEG (Knowledge Ark) - M0a build foundation";

  # Pinned on purpose: the concept forbids floating inputs. Verified to expose
  # every cross set named in nix/targets.nix.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f68407657ad294471eb4b2e65d193df26edf729f";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      matrix = pkgs: import ./nix/targets.nix { inherit pkgs; };
      probes = pkgs: import ./nix/probe.nix { inherit lib pkgs; };

      # Flat names so one build is one short command:
      #   nix build .#probe-aarch64-kernel
      #   nix build .#probe-armv7-mupdf-fallback
      flat = pkgs: select: suffix:
        lib.listToAttrs (lib.concatLists (lib.mapAttrsToList (name: t:
          let
            c = (probes pkgs).${select} name t;
          in
          map (comp: lib.nameValuePair "probe-${name}-${comp}${suffix}" c.${comp})
            (lib.attrNames c))
          (matrix pkgs).targets));

      probeOutputs = pkgs:
        (flat pkgs "components" "")
        // (flat pkgs "fallbackComponents" "-fallback");
    in
    {
      packages = forAll (pkgs: {
        targets = pkgs.writeText "kovcheg-targets.json"
          (builtins.toJSON (matrix pkgs).metadata);
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          # Deliberately light: qemu and image tools belong to the next plan.
          packages = with pkgs; [ python3 jq curl xz cpio diffutils file binutils flock time ];
        };
      });

      checks = forAll (pkgs: {
        targets-present =
          let
            m = matrix pkgs;
            names = builtins.attrNames m.targets;
            missing = builtins.filter (n: !(builtins.elem n names)) m.expectedNames;
          in
          pkgs.runCommand "kovcheg-targets-present" { } (
            if missing == [ ]
            then "mkdir -p $out; echo 'all five targets present' > $out/report.txt"
            else "echo 'missing targets: ${lib.concatStringsSep "," missing}' >&2; exit 1"
          );

        # Every target must expose all four components, in both set variants.
        probes-complete =
          let
            c = probeOutputs pkgs;
            names = builtins.attrNames c;
            wanted = lib.concatLists (lib.mapAttrsToList (name: t:
              map (comp: "probe-${name}-${comp}") [ "selftest" "busybox" "kernel" "mupdf" ])
              (matrix pkgs).targets);
            missing = builtins.filter (n: !(builtins.elem n names)) wanted;
          in
          pkgs.runCommand "kovcheg-probes-complete" { } (
            if missing == [ ]
            then "mkdir -p $out; echo 'all probe outputs present' > $out/report.txt"
            else "echo 'missing probes: ${lib.concatStringsSep "," missing}' >&2; exit 1"
          );
      });
    }
    // probeOutputs nixpkgs.legacyPackages.x86_64-linux;
}
