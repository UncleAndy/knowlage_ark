# KOVCHEG per-target component probes (M0a).
#
# Components: the static selftest binary, a static busybox, the kernel with our
# config fragment applied, and MuPDF (the component most likely to fail on
# armv7/riscv64). Fallback variants rebuild the userland components with the
# target's fallback set, per §8 of the concept.
{ lib, pkgs }:
let
  k = lib.kernel;

  # The fragment stays deliberately small in M0a: we only need to prove it
  # applies and the kernel still builds. The full minimal config is plan 2 work.
  common = {
    FB = k.yes;
    FB_CONSOLE = k.yes;
    FRAMEBUFFER_CONSOLE = k.yes;
    VT = k.yes;
    DRM_SIMPLEDRM = k.yes;
    INPUT = k.yes;
    INPUT_EVDEV = k.yes;
    INPUT_MOUSEDEV = k.yes;
    HID_GENERIC = k.yes;
    HID_MULTITOUCH = k.yes;
    USB_HID = k.yes;
    USB_STORAGE = k.yes;
    EXFAT_FS = k.yes;
    VFAT_FS = k.yes;
    ISO9660_FS = k.yes;
    TMPFS = k.yes;
    DEVTMPFS = k.yes;
    DEVTMPFS_MOUNT = k.yes;
    RD_GZIP = k.yes;
  };

  x86Only = {
    FB_VESA = k.yes;
    FB_EFI = k.yes;
    FB_VGA16 = k.yes;
    FB_VGA_CONSOLE = k.yes;
  };

  layerCOnly = {
    MMC = k.yes;
    MMC_BLOCK = k.yes;
    MMC_SDHCI = k.yes;
    MMC_SDHCI_PLTFM = k.yes;
  };

  fragment = t:
    common
    // lib.optionalAttrs (t.arch == "x86_64" || t.arch == "i686") x86Only
    // lib.optionalAttrs (t.bootLayer == "C") layerCOnly;

  force = attrs: lib.mapAttrs (n: v: lib.mkForce v) attrs;

  selftestOf = t: set: pkgs.callPackage ./selftest.nix {
    pkgsStatic = set.pkgsStatic;
    inherit (pkgs) binutils;
    src = ../probe;
    arch = t.selftestArch;
    machine = t.elfMachine;
    # 32-bit x86 binaries run on an x86_64 host; everything else is readelf-only.
    runHere = (t.arch == "x86_64" || t.arch == "i686");
  };

  userland = t: set: {
    selftest = selftestOf t set;
    busybox = set.pkgsStatic.busybox;
    mupdf = set.mupdf;
  };

  components = name: t:
    (userland t t.userlandSet) // {
      kernel = (t.kernelSet.linuxPackages.kernel).override {
        structuredExtraConfig = force (fragment t);
      };
      kernelDefault = t.kernelSet.linuxPackages.kernel;
    };

  fallbackComponents = name: t: userland t t.userlandSetFallback;
in
{
  inherit components fallbackComponents fragment;
}