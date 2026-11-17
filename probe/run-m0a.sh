#!/usr/bin/env bash
# KOVCHEG M0a toolchain runner.
#
# Sequential by design: timings are comparable only when nothing else builds at
# the same time. Every row records the nixpkgs set that produced it and its
# provenance (cache / local / rebuilt) - a five-second "build" is a fetch, not
# a build, and this runner must never report it as one.
set -u

usage() { echo "usage: $0 pass1|pass2 [--rebuild] [--targets \"a b\"]" >&2; exit 2; }

pass="${1:-}"; shift || true
case "$pass" in
  pass1) default_targets="x86_64 aarch64" ;;
  pass2) default_targets="i686 armv7 riscv64" ;;
  *) usage ;;
esac

rebuild=""
targets="$default_targets"
while [ $# -gt 0 ]; do
  case "$1" in
    --rebuild) rebuild="yes" ;;
    --targets) shift; targets="${1:-}"; [ -n "$targets" ] || usage ;;
    *) usage ;;
  esac
  shift
done

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
mkdir -p docs/reports
stamp="$(date +%F)"
out="docs/reports/${stamp}-m0a-toolchain-${pass}.tsv"
components="selftest busybox kernel mupdf"

rev="$(nix flake metadata --json | nix shell nixpkgs#python3 --command python3 -c \
  'import json,sys; print(json.load(sys.stdin)["locks"]["nodes"]["nixpkgs"]["locked"]["rev"])')"

free_gb() { df -BG --output=avail /nix | tail -1 | tr -dc '0-9'; }

arch_note() { # target comp path
  local comp="$2"
  local path="$3"
  if [ "$comp" = "selftest" ] && [ -f "$path/share/headers.txt" ]; then
    printf '%s | %s' \
      "$(grep -m1 'Machine:' "$path/share/headers.txt" | tr -s ' ' | cut -d: -f2- | sed 's/^ //')" \
      "$(grep -m1 '^selftest ' "$path/share/run.txt" || echo 'not executed')"
  fi
}

build_one() { # target comp attr setname
  local target="$1" comp="$2" attr="$3" setname="$4"
  local s e path rc err provenance size note
  err="$(mktemp)"
  s="$(date +%s)"
  # A derivation can have several outputs (mupdf ships -bin and -man): keep them
  # all, but never let a newline leak into a TSV field.
  if [ -n "$rebuild" ]; then
    paths="$(nix build --no-link --print-out-paths --rebuild "$attr" 2>"$err")"; rc=$?
  else
    paths="$(nix build --no-link --print-out-paths "$attr" 2>"$err")"; rc=$?
  fi
  path="$(printf '%s' "$paths" | tr '\n' ',')"
  e="$(date +%s)"
  if [ $rc -ne 0 ]; then
    # Keep the whole reason: a truncated last line hid a real cause once.
    printf '%s\t%s\t%s\tFAIL\t-\t%s\t-\t-\t%s\n' "$target" "$comp" "$setname" "$((e-s))" \
      "$(grep -v '^warning:' "$err" | tail -3 | tr '\n\t' '  ' | cut -c1-400)" | tee -a "$out"
    rm -f "$err"; return 1
  fi
  if grep -q 'copying path .* from https://cache.nixos.org' "$err"; then
    provenance=cache
  elif [ -n "$rebuild" ]; then
    provenance=rebuilt
  else
    provenance=local
  fi
  size="$(printf '%s' "$paths" | tr '\n' '\0' | xargs -0 du -sb 2>/dev/null | awk '{s+=$1} END {print s+0}')"
  note="$(arch_note "$target" "$comp" "$(printf '%s\n' "$paths" | head -1)")"
  printf '%s\t%s\t%s\tPASS\t%s\t%s\t%s\t%s\t%s\n' "$target" "$comp" "$setname" \
    "$provenance" "$((e-s))" "$size" "$path" "$note" | tee -a "$out"
  rm -f "$err"; return 0
}

{
  printf '# KOVCHEG M0a toolchain run: %s\n' "$pass"
  printf '# nixpkgs rev: %s\n' "$rev"
  printf '# nproc: %s\n' "$(nproc)"
  printf '# rebuild: %s\n' "${rebuild:-no}"
  printf '# free /nix before: %sG\n' "$(free_gb)"
  printf 'target\tcomponent\tset\tstatus\tprovenance\tseconds\tsizeBytes\tstorePath\tnote\n'
} | tee "$out"

for target in $targets; do
  verdict=PASS; reason=""
  for comp in $components; do
    if [ "$(free_gb)" -lt 20 ]; then
      printf '%s\t%s\t-\tSKIP\t-\t0\t-\t-\tstopped: less than 20G free in /nix\n' "$target" "$comp" | tee -a "$out"
      verdict=FAIL; reason="ran out of disk"; break
    fi
    if ! build_one "$target" "$comp" ".#probe-${target}-${comp}" preferred; then
      if [ "$comp" = "kernel" ]; then
        printf '%s\t%s\t-\tFAIL\t-\t0\t-\t-\tno fallback set exists for the kernel\n' "$target" "$comp" | tee -a "$out"
        verdict=FAIL; reason="${reason:+$reason; }kernel failed with the configured fragment"
      elif build_one "$target" "$comp" ".#probe-${target}-${comp}-fallback" fallback; then
        [ "$verdict" = "PASS" ] && verdict=PARTIAL
        reason="${reason:+$reason; }${comp} needed the fallback set"
      else
        verdict=FAIL; reason="${reason:+$reason; }${comp} failed in both sets"
      fi
    fi
  done
  printf 'VERDICT\t%s\t%s\t%s\n' "$target" "$verdict" "${reason:-all components built}" | tee -a "$out"
done

printf '# free /nix after: %sG\n' "$(free_gb)" | tee -a "$out"
printf '# report: %s\n' "$out"
