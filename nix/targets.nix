# KOVCHEG target matrix (M0a).
#
# Every entry names the nixpkgs sets used to cross-build the payload for that
# architecture, plus the fallback set to retry with when the preferred set does
# not build. Sets are verified to exist at the pinned nixpkgs revision
# (f68407657ad294471eb4b2e65d193df26edf729f, nixos-26.05) - see §0 item 6 and
# §8 of the concept.
{ pkgs }:
let
  target = { arch, userlandSetName, userlandSet, userlandSetFallbackName,
             userlandSetFallback, kernelSetName, kernelSet, firmware,
             bootLayer, selftestArch, elfMachine, note }:
    { inherit arch userlandSetName userlandSet userlandSetFallbackName
              userlandSetFallback kernelSetName kernelSet firmware bootLayer
              selftestArch elfMachine note; };

  targets = {
    x86_64 = target {
      arch = "x86_64";
      userlandSetName = "pkgsMusl";
      userlandSet = pkgs.pkgsMusl;
      userlandSetFallbackName = "plain";
      userlandSetFallback = pkgs;
      kernelSetName = "plain";
      kernelSet = pkgs;
      firmware = "bios+uefi-x64";
      bootLayer = "A";
      selftestArch = "x86_64";
      elfMachine = "Advanced Micro Devices X86-64";
      note = "Ventoy native: i386-pc for BIOS, BOOTX64.EFI for UEFI";
    };

    i686 = target {
      arch = "i686";
      userlandSetName = "pkgsCross.musl32";
      userlandSet = pkgs.pkgsCross.musl32;
      userlandSetFallbackName = "pkgsCross.gnu32";
      userlandSetFallback = pkgs.pkgsCross.gnu32;
      kernelSetName = "pkgsCross.gnu32";
      kernelSet = pkgs.pkgsCross.gnu32;
      firmware = "bios+uefi-ia32";
      bootLayer = "A";
      selftestArch = "i386";
      elfMachine = "Intel 80386";
      note = "old BIOS and 32-bit UEFI; PAE off for pre-2005 CPUs";
    };

    aarch64 = target {
      arch = "aarch64";
      userlandSetName = "pkgsCross.aarch64-multiplatform-musl";
      userlandSet = pkgs.pkgsCross.aarch64-multiplatform-musl;
      userlandSetFallbackName = "pkgsCross.aarch64-multiplatform";
      userlandSetFallback = pkgs.pkgsCross.aarch64-multiplatform;
      kernelSetName = "pkgsCross.aarch64-multiplatform";
      kernelSet = pkgs.pkgsCross.aarch64-multiplatform;
      firmware = "uefi-arm64";
      bootLayer = "B";
      selftestArch = "aarch64";
      elfMachine = "AArch64";
      note = "Ventoy BOOTAA64.EFI; boards without UEFI go through layer C";
    };

    armv7 = target {
      arch = "armv7";
      userlandSetName = "pkgsCross.muslpi";
      userlandSet = pkgs.pkgsCross.muslpi;
      userlandSetFallbackName = "pkgsCross.armv7l-hf-multiplatform";
      userlandSetFallback = pkgs.pkgsCross.armv7l-hf-multiplatform;
      kernelSetName = "pkgsCross.armv7l-hf-multiplatform";
      kernelSet = pkgs.pkgsCross.armv7l-hf-multiplatform;
      firmware = "u-boot distro-boot";
      bootLayer = "C";
      selftestArch = "arm";
      elfMachine = "ARM";
      note = "no Ventoy support at all: extlinux on the ARKBOOT partition";
    };

    riscv64 = target {
      arch = "riscv64";
      userlandSetName = "pkgsCross.riscv64-musl";
      userlandSet = pkgs.pkgsCross.riscv64-musl;
      userlandSetFallbackName = "pkgsCross.riscv64";
      userlandSetFallback = pkgs.pkgsCross.riscv64;
      kernelSetName = "pkgsCross.riscv64";
      kernelSet = pkgs.pkgsCross.riscv64;
      firmware = "u-boot distro-boot";
      bootLayer = "C";
      selftestArch = "riscv";
      elfMachine = "RISC-V";
      note = "UEFI boards exist, but Ventoy has no RISC-V loader: layer C only";
    };
  };

  # What can be dumped to JSON: the sets themselves are derivations and are not.
  metadata = builtins.mapAttrs (name: t:
    builtins.removeAttrs t [ "userlandSet" "userlandSetFallback" "kernelSet" ]) targets;
in
{
  inherit targets metadata;
  expectedNames = [ "x86_64" "i686" "aarch64" "armv7" "riscv64" ];
}
