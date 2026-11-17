# KOVCHEG M0a — Build Foundation and Toolchain Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. NOTE: the owner of this project prohibits delegation, so execution is native (superpowers:executing-plans) — the subagent option is left here only because the plan template requires it.

**Goal:** prove that every byte KOVCHEG needs can be cross-built from source in one flake for the five target architectures, and produce a measured report of what builds, what takes how long, and what fails.

**Architecture:** one `flake.nix` at the repo root pins nixpkgs and exposes (a) a per-target matrix of nixpkgs cross sets, (b) probe derivations that build a static self-test binary, a kernel and MuPDF per target, (c) a runner that builds each probe sequentially, records real numbers and emits a TSV plus a verdict per target. Nothing boots yet: M0a ends at buildable, measured artifacts.

**Tech Stack:** Nix flakes (nix 2.34 on the build machine), nixpkgs cross sets with musl where available, C99 for the probe binary, POSIX shell + Python (via `nix shell nixpkgs#python3`) for the report runner.

**Spec:** `drafts/2026-11-17-koncepciya-kovcheg-znanij.md` (concept, approved 2026-11-17) — §8 (build, variant B), §5 (payload per architecture), §9 (acceptance), §11 (M0a).

## Global Constraints

- All bytes built from source inside this flake. The only declared exception is Ventoy (`§8`, exception #1) and in M0a it is not touched at all.
- nixpkgs is pinned by revision in `flake.lock`; every probe records the exact `nixpkgs` revision it was built with.
- musl is the default libc, static linking (`pkgsStatic`) wherever it links. glibc is only used as a recorded fallback per target, never as a silent one.
- Attribute existence is never evidence of a successful build. Only a completed build counts as PASS; a probe that fails is reported FAIL with the captured error, and the report continues.
- All numbers are measured on this machine, one build at a time, with `nproc` recorded. No estimated timings in the report.
- Every task ends with a commit; `git status` is clean between tasks.
- Every report row carries its provenance: `cache` (substituted from cache.nixos.org), `local` (compiled on this machine), `rebuilt` (compiled here with `--rebuild`). A five-second `nix build` is a fetch, not a build, and its duration is never quoted as a build time.

## Review Focus

1. **Per-component failure isolation.** A single failing probe (say MuPDF on riscv64) must not abort the run: the report still lists results for the remaining components and targets. Expected: exit code 0 with FAIL rows, non-zero only when nothing at all could be built.
2. **libc provenance.** A PASS row must say which set produced it (`pkgsCross.aarch64-multiplatform-musl` vs `pkgsCross.aarch64-multiplatform`). A PASS without a recorded libc is treated as unusable data.
3. **Attribute-existence shortcut.** No task may mark a target PASS from an `eval`/`tryEval` check; that already produced a false positive once (§0 item 6 of the concept).
4. **Timing hygiene.** Builds run sequentially; the report records whether the run was sequential and the core count, so a later comparison is not noise.
5. **Disk growth.** Cross sets pull whole toolchains. The runner records free space in `/nix` before and after and stops launching new components below 20 GB free.
6. **Provenance in every row.** Already caught once: the first `nix build` of static busybox finished in 4.99 s because it was substituted from the binary cache, not compiled. Any row whose artifact was substituted is marked `cache` and its duration is not quoted as a build time.

## Plan series (context, not part of this plan)

| # | Plan | Subsystem | Produces |
|---|---|---|---|
| 1 | **this one** | build foundation + toolchain spike | measured per-target build report |
| 2 | kovcheg-m0b-reader | readers spike | x86_64 ISO booting in QEMU, PDF from ZIP on screen, keyboard paging |
| 3 | kovcheg-input-library | input layer + index | touch/mouse pan, document list from the index, search |
| 4 | kovcheg-architectures | multi-arch images + ARKBOOT | i686/aarch64 ISOs, U-Boot distro-boot partition |
| 5 | kovcheg-integrity | par2, manifests, recovery kit | corruption drill passes, stick rebuildable from itself |
| 6 | kovcheg-hardening | real hardware matrix | measured hardware matrix, documented failures |

Plans 2-6 are written after M0a reports real numbers, because those numbers decide which targets survive.

---

### Task 1: Repo skeleton and pinned flake

**Files:**
- Create: `flake.nix`, `flake.lock`, `README.md`, `.gitignore` (append)
- Create: `nix/targets.nix`

**Interfaces:**
- Produces: flake outputs `devShells.<system>.default`, `packages.<system>.targets` (a `writeText` JSON dump of `nix/targets.nix`), and the pinned `inputs.nixpkgs`.
- `nix/targets.nix` exports an attrset keyed by target name; each value is `{ arch, userlandSet, userlandSetFallback, kernelSet, firmware, bootLayer, note }` where the sets are functions of `nixpkgs.legacyPackages.x86_64-linux`.

- [ ] **Step 1: Write `nix/targets.nix` with the five verified targets**

Keys and values: `x86_64` (userlandSet `p.pkgsMusl`, fallback `p`, kernelSet `p`, firmware `bios+uefi-x64`, bootLayer `A`), `i686` (`p.pkgsCross.musl32`, fallback `p.pkgsCross.gnu32`, kernelSet `p.pkgsCross.gnu32`, `bios+uefi-ia32`, `A`), `aarch64` (`p.pkgsCross.aarch64-multiplatform-musl`, fallback `p.pkgsCross.aarch64-multiplatform`, kernelSet the same fallback set, `uefi-arm64`, `B`), `armv7` (`p.pkgsCross.muslpi`, fallback `p.pkgsCross.armv7l-hf-multiplatform`, kernelSet the fallback set, `u-boot distro-boot`, `C`), `riscv64` (`p.pkgsCross.riscv64-musl`, fallback `p.pkgsCross.riscv64`, kernelSet the fallback set, `u-boot distro-boot`, `C`). Kernel set is taken from the glibc set where the musl set's kernel set is not what we want to boot.

- [ ] **Step 2: Write `flake.nix`**

`inputs.nixpkgs` from the flake registry is not acceptable — pin an explicit `github:NixOS/nixpkgs/<rev>` (take the rev currently resolved by `nix flake metadata nixpkgs --json | jq -r .revision`). Outputs: `devShells.default` with `python3`, `jq`, `curl`, `xorriso`, `mtools`, `qemu` (for later plans), `pkgsStatic.busybox`; `packages.targets = pkgs.writeText "kovcheg-targets.json" (builtins.toJSON (import ./nix/targets.nix { pkgs = ...; }))`; `apps.probe` pointing at the Task 3 runner.

- [ ] **Step 3: Verify**

Run: `nix develop -c nix --version` and `nix eval .#packages.x86_64-linux.targets` (expect a store path). Run: `nix run .#probe -- list` — before Task 3 exists this must fail loudly, not silently pass.
Expected: dev shell opens, targets path printed.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock nix/targets.nix README.md .gitignore
git commit -m "build: pin nixpkgs and add the five-target matrix"
```

### Task 2: Static self-test binary

**Files:**
- Create: `probe/selftest.c`

**Interfaces:**
- Produces: a C99 program that prints one line `selftest arch=<arch> ptr=<bits> endian=<le|be> static=<yes|no>` and exits 0. `arch` comes from compiler macros (`__x86_64__`, `__i386__`, `__aarch64__`, `__arm__`, `__riscv`), `bits` from `sizeof(void*)*8`, `endian` from `__BYTE_ORDER__`.

- [ ] **Step 1: Write the program** — no libc beyond `printf`, so it links statically with musl without surprises.

- [ ] **Step 2: Verify natively**

Run: `nix shell nixpkgs#gcc --command sh -c 'cc -static -O2 -o /tmp/selftest probe/selftest.c && /tmp/selftest'`
Expected: `selftest arch=x86_64 ptr=64 endian=le static=yes`

- [ ] **Step 3: Commit**

```bash
git add probe/selftest.c
git commit -m "feat(probe): add the static self-test binary"
```

### Task 3: Probe derivations per target

**Files:**
- Create: `nix/probe.nix`

**Interfaces:**
- Produces: `mkProbe target` → derivation whose `$out` contains `selftest`, `busybox`, `kernel/config` (the built kernel's `.config`), `mupdf/` (either a static lib or the shared library, whatever the set builds), and `report.json` with `{ target, component, set, status, seconds, sizeBytes, storePath, error }` rows.
- Consumes: `nix/targets.nix` (Task 1), `probe/selftest.c` (Task 2).

- [ ] **Step 1: Build the static busybox per target as the first real probe** (component `busybox`), using the target's `userlandSet.pkgsStatic.busybox`; on failure record the captured stderr and retry once with `userlandSetFallback`.
- [ ] **Step 2: Add the `selftest` component** — compile `probe/selftest.c` with the target's `pkgsStatic` stdenv into a static binary, and assert the arch string matches the target key (a build that silently produces the wrong arch is a FAIL). Verification is by `readelf` (ELF machine string plus absence of `PT_INTERP`), because cross-built binaries cannot be executed on the build host; executing them under `qemu-user` belongs to plan 2. Never mark a cross target PASS from the fact that its derivation evaluated.
- [ ] **Step 3: Add the `kernel` component** — build `kernelSet.linuxPackages.kernel` first with the default config (baseline); then a second component `kernel-config` that applies our fragment via `structuredExtraConfig` with the §5 option set (`FB_VESA`, `FB_EFI`, `FB_VGA16`, `DRM_SIMPLEDRM`, `INPUT_EVDEV`, `INPUT_MOUSEDEV`, `HID_MULTITOUCH`, `USB_HID`, `USB_STORAGE`, `EXFAT_FS`, `VFAT_FS`, `ISO9660`, `MMC` for layer C targets) and greps the resulting `.config` for each option, failing if any is absent. If `structuredExtraConfig` is not accepted by the pinned nixpkgs, record that and use `linuxPackages_custom` with a `configfile` produced by `make defconfig` plus the fragment; the report must say which mechanism was used.
- [ ] **Step 4: Add the `mupdf` component** — build `userlandSet.mupdf` (the risky one); record whether it produced a static or shared artifact and its size. On failure: record the error, then retry with the fallback set, then (only if both fail) mark the target FAIL for mupdf and continue.
- [ ] **Step 5: Run pass 1 (x86_64, aarch64) manually and fix what breaks.** Long builds — run in the background with a completion notification, one at a time.
- [ ] **Step 6: Compile the critical components on purpose** — kernel, MuPDF and busybox with `--rebuild`, so each target has at least one genuinely from-source measurement, recorded separately from the substituted rows.

- [ ] **Step 7: Commit**

```bash
git add nix/probe.nix
git commit -m "feat(probe): build selftest, busybox, kernel and mupdf per target"
```

### Task 4: Report runner and verdicts

**Files:**
- Create: `probe/report.sh` (entry point for `nix run .#probe`), `docs/reports/.gitkeep`

**Interfaces:**
- Consumes: `mkProbe` from Task 3.
- Produces: `docs/reports/YYYY-MM-DD-m0a-toolchain-<pass>.tsv` with the columns `target  component  set  status  seconds  sizeBytes  storePath  error` and a trailing block `VERDICT <target> <PASS|PARTIAL|FAIL> <reason>`; prints the same verdict block to stdout.

- [ ] **Step 1: Write the runner** — arguments `pass1` (x86_64, aarch64) and `pass2` (i686, armv7, riscv64); sequential builds; records `nproc` and free `/nix` space before and after; stops launching new components below 20 GB free and says so in the report; each row carries `provenance` (`cache` when the build output contains `copying path ... from https://cache.nixos.org`, otherwise `local` or `rebuilt`).
- [ ] **Step 2: Verify failure isolation** — temporarily point one target at a deliberately broken set name, run `pass1`, confirm the run completes with a FAIL row and exit code 0, then revert.
- [ ] **Step 3: Run pass 1 for real, in the background with notification, and paste the verdict block into the commit message.**
- [ ] **Step 4: Commit**

```bash
git add probe/report.sh docs/reports/
git commit -m "feat(probe): add the sequential report runner and verdicts (pass1)"
```

### Task 5: Pass 2 (i686, armv7, riscv64) against the recorded expectations

**Files:**
- Modify: `nix/targets.nix` (only if a fallback has to be promoted for a target)
- Create: `docs/reports/YYYY-MM-DD-m0a-toolchain-pass2.tsv`

- [ ] **Step 1: Run pass 2 in the background with notification.** Expect MuPDF to be the failure point on armv7 and riscv64.
- [ ] **Step 2: Apply the pre-agreed fallbacks in order** (§8 of the concept): (a) same target with the glibc set, (b) our own overlay patch, (c) target drops out of v1. Record which one was used for which component.
- [ ] **Step 3: Do not tune any threshold after seeing the numbers.** If a target fails, it fails; the plan records it and the decision moves to the owner.
- [ ] **Step 4: Commit**

```bash
git add nix/targets.nix docs/reports/
git commit -m "docs(reports): record the M0a toolchain results for both passes"
```

### Task 6: Hand-off note

**Files:**
- Create: `docs/reports/2026-11-17-m0a-summary.md`
- Modify: `README.md`

- [ ] **Step 1: Write the summary**: per target — builds/does not build, minutes, sizes, which set, which fallback, and the one-line consequence for the next plan. Table of the five targets plus a short "what would change my mind" line.
- [ ] **Step 2: Update `README.md`** with the two commands that reproduce the run (`nix run .#probe -- pass1`, `pass2`) and where the reports live.
- [ ] **Step 3: Commit**

```bash
git add docs/reports/2026-11-17-m0a-summary.md README.md
git commit -m "docs: M0a summary and reproduction commands"
```

---

## M0a exit criteria

- `docs/reports/2026-11-17-m0a-toolchain-pass1.tsv` and `-pass2.tsv` exist with real rows; every row names the set that produced it.
- Every target has a verdict: PASS, PARTIAL (with the named fallback) or FAIL (with the captured error).
- The x86_64 and aarch64 rows are PASS or PARTIAL; a FAIL on both means the toolchain decision (variant B) needs the owner before any reader work.
- `nix run .#probe -- pass1` is reproducible from a clean checkout.
- Every row names its provenance, and the summary states how many artifacts were compiled on this machine versus substituted from the cache.
- No reader, boot image or ISO work has started in this plan.