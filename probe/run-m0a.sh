#!/usr/bin/env bash
# KOVCHEG M0a toolchain runner.
#
# Sequential by design: timings are comparable only when nothing else builds at
# the same time. Every row records the nixpkgs set that produced it and its
# provenance, because a five-second "nix build" is a substitution from the
# binary cache, not a compilation.
#
# Provenance values:
#   present - the artifact was already valid in the store, nothing happened
#   cache   - substituted from cache.nixos.org
#   local   - compiled here (this is the from-source number)
#   rebuilt - compiled here after the artifact already existed (forced)
#
# --rebuild means "recompile even though the artifact is already there". It is
# NOT "force a compile": Nix refuses it when the outputs are neither valid nor
# substitutable ("some outputs ... are not valid, so checking is not possible").
# So a first build is always plain, and a forced recompile follows only once the
# artifact exists.
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
critical="busybox kernel mupdf"   # selftest builds in seconds, not worth forcing

rev="$(nix flake metadata --json | nix shell nixpkgs#python3 --command python3 -c \
  'import json,sys; print(json.load(sys.stdin)["locks"]["nodes"]["nixpkgs"]["locked"]["rev"])')"

free_gb() { df -BG --output=avail /nix | tail -1 | tr -dc '0-9'; }
is_critical() { case " $critical " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

row() { # target comp setname status provenance seconds size paths note
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}" "${8:-}" "$9" | tee -a "$out"
}

reason() { grep -v '^warning:' "$1" | tail -3 | tr '\n\t' '  ' | cut -c1-400; }

arch_note() { # comp mainpath
  local comp="$1" path="$2"
  if [ "$comp" = "selftest" ] && [ -f "$path/share/headers.txt" ]; then
    printf '%s | %s' \
      "$(grep -m1 'Machine:' "$path/share/headers.txt" | tr -s ' ' | cut -d: -f2- | sed 's/^ //')" \
      "$(grep -m1 '^selftest ' "$path/share/run.txt" || echo 'not executed')"
  fi
}

# build_run <attr> <extra-args...>: sets RC, PATHS, ERR, SECONDS_TAKEN, PROV
build_run() {
  local attr="$1"; shift
  local s e main
  ERR="$(mktemp)"
  main="$(nix eval --raw "$attr.outPath" 2>/dev/null || true)"
  PROV=unknown
  if [ -n "$main" ] && nix path-info "$main" >/dev/null 2>&1; then
    PROV=present
  fi
  s="$(date +%s)"
  PATHS="$(nix build --no-link --print-out-paths "$@" "$attr" 2>"$ERR")"; RC=$?
  e="$(date +%s)"
  SECONDS_TAKEN="$((e-s))"
  if [ $RC -eq 0 ] && [ "$PROV" = "unknown" ]; then
    if grep -q 'copying path .* from https://cache.nixos.org' "$ERR"; then PROV=cache; else PROV=local; fi
  fi
  rm -f "$ERR"; ERR="$(mktemp)"; return 0
}

# run_component <target> <comp> <attr> <setname>
run_component() {
  local target="$1" comp="$2" attr="$3" setname="$4"
  local paths err_file size note prov

  err_file="$(mktemp)"
  if ! nix build --no-link --print-out-paths "$attr" >/dev/null 2>"$err_file"; then
    row "$target" "$comp" "$setname" FAIL - 0 "" "" "$(reason "$err_file")"
    rm -f "$err_file"; return 1
  fi
  rm -f "$err_file"

  # Plain build first, timed and measured.
  build_run "$attr"
  paths="$PATHS"; prov="$PROV"
  size="$(printf '%s' "$paths" | tr '\n' '\0' | xargs -0 du -sb 2>/dev/null | awk '{s+=$1} END {print s+0}')"
  note="$(arch_note "$comp" "$(printf '%s\n' "$paths" | head -1)")"
  row "$target" "$comp" "$setname" PASS "${prov}" "$SECONDS_TAKEN" "$size" \
    "$(printf '%s' "$paths" | tr '\n' ',')" "$note"

  # Then, for critical components, a genuine recompile if nothing was compiled above.
  if [ -n "$rebuild" ] && is_critical "$comp" && [ "$prov" != "local" ]; then
    build_run "$attr" --rebuild
    if [ $RC -ne 0 ]; then
      row "$target" "$comp" "$setname" FAIL - "$SECONDS_TAKEN" "" "" "--rebuild refused: $(tail -2 "$ERR" | tr '\n\t' '  ' | cut -c1-300)"
      return 0
    fi
    paths="$PATHS"
    size="$(printf '%s' "$paths" | tr '\n' '\0' | xargs -0 du -sb 2>/dev/null | awk '{s+=$1} END {print s+0}')"
    row "$target" "$comp" "$setname" PASS "rebuilt" "$SECONDS_TAKEN" "$size" \
      "$(printf '%s' "$paths" | tr '\n' ',')" "forced local recompile (was ${prov})"
  fi
  return 0
}

{
  printf '# KOVCHEG M0a toolchain run: %s\n' "$pass"
  printf '# nixpkgs rev: %s\n' "$rev"
  printf '# nproc: %s\n' "$(nproc)"
  printf '# rebuild requested: %s\n' "${rebuild:-no}"
  printf '# free /nix before: %sG\n' "$(free_gb)"
  printf 'target\tcomponent\tset\tstatus\tprovenance\tseconds\tsizeBytes\tstorePath\tnote\n'
} | tee "$out"

for target in $targets; do
  verdict=PASS; reason_txt=""
  for comp in $components; do
    if [ "$(free_gb)" -lt 20 ]; then
      row "$target" "$comp" - SKIP - 0 "" "" "stopped: less than 20G free in /nix"
      verdict=FAIL; reason_txt="ran out of disk"; break
    fi
    if ! run_component "$target" "$comp" ".#probe-${target}-${comp}" preferred; then
      if [ "$comp" = "kernel" ]; then
        row "$target" "$comp" - FAIL - 0 "" "" "no fallback set exists for the kernel"
        verdict=FAIL; reason_txt="${reason_txt:+$reason_txt; }kernel failed with the configured fragment"
      elif run_component "$target" "$comp" ".#probe-${target}-${comp}-fallback" fallback; then
        [ "$verdict" = "PASS" ] && verdict=PARTIAL
        reason_txt="${reason_txt:+$reason_txt; }${comp} needed the fallback set"
      else
        verdict=FAIL; reason_txt="${reason_txt:+$reason_txt; }${comp} failed in both sets"
      fi
    fi
  done
  printf 'VERDICT\t%s\t%s\t%s\n' "$target" "$verdict" "${reason_txt:-all components built}" | tee -a "$out"
done

printf '# free /nix after: %sG\n' "$(free_gb)" | tee -a "$out"
printf '# report: %s\n' "$out"
