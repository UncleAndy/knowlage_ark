# KOVCHEG probe binary: proves a target toolchain produced a static binary of
# the expected architecture.
#
# Verification is deliberately two-part:
#   - always: readelf on the ELF header and program headers (architecture name,
#     absence of PT_INTERP). This works for foreign architectures too, so it is
#     valid for cross targets that cannot be executed here.
#   - only when runHere is set: run the binary and
#     match its own arch string. Cross targets report "not executed" instead of
#     pretending; executing them under qemu-user arrives with plan 2.
{ lib, pkgsStatic, binutils, runHere ? true, src ? ./../probe, arch ? null, machine ? null }:
pkgsStatic.stdenv.mkDerivation {
  pname = "kovcheg-selftest";
  version = "0.1.0";
  inherit src;
  dontConfigure = true;

  # Host binutils: readelf reads ELF headers of any architecture.
  nativeBuildInputs = [ binutils ];

  buildPhase = ''
    runHook preBuild
    $CC -static -O2 -Wall -Wextra -o selftest selftest.c
    readelf -h selftest > headers.txt
    readelf -l selftest > segments.txt

    if grep -q INTERP segments.txt; then
      echo "FAIL: selftest is dynamically linked, expected static" >&2
      exit 1
    fi

    ${lib.optionalString (machine != null) ''
      if ! grep -q "Machine:.*${machine}" headers.txt; then
        echo "FAIL: expected machine '${machine}', got:" >&2
        cat headers.txt >&2
        exit 1
      fi
    ''}

    ${if runHere then ''
      ./selftest | tee run.txt
    '' else ''
      echo "not executed: cross-built target here; emulator execution arrives with plan 2" | tee run.txt
    ''}

    ${lib.optionalString (arch != null) ''
      if grep -q '^selftest ' run.txt; then
        grep -q "^selftest arch=${arch} " run.txt || {
          echo "FAIL: expected arch=${arch}, got: $(cat run.txt)" >&2
          exit 1
        }
      fi
    ''}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share
    cp selftest $out/bin/selftest
    cp headers.txt segments.txt run.txt $out/share/
    runHook postInstall
  '';

  meta = {
    description = "KOVCHEG static self-test binary";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
