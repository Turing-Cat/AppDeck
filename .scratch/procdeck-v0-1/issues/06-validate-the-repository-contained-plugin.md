# 06: Validate the repository-contained ProcDeck v0.1 plugin

**What to build:** Deliver a minimal, repository-contained ProcDeck v0.1 implementation whose documented contract, model behavior, plugin metadata, and target-platform compatibility are verified before any user configuration is changed.

**Blocked by:** 03: Focus the Selected App; 04: Gracefully Close the Selected App; 05: Force Kill the Selected App after confirmation.

**Status:** resolved

- [x] The repository contains only the required plugin manifest, shell entry component, pure dependency-free model, one Node self-check, product documentation, license, and existing design records.
- [x] No package manager, build step, daemon, helper executable, install hook, settings subsystem, resource metrics, independent theme palette, marketplace files, or speculative component hierarchy is introduced.
- [x] The product status records ProcDeck v0.1 as implemented and repository-verified, and destructive-action wording consistently describes exact Hyprland window owners rather than inferred processes.
- [x] The dependency-free Node self-check passes and covers the acceptance-critical model behavior accumulated by the preceding tickets.
- [x] Omarchy plugin validation passes against the supported Omarchy 4.0.2 contract.
- [x] The shell entry component loads without warnings against Quickshell 0.3.1 and Hyprland 0.56.2 APIs.
- [x] Repository verification does not create a development symlink, enable the plugin, rescan or toggle the user's shell, modify Omarchy or Hyprland configuration, or claim that the desktop smoke matrix has run.
- [x] The verification report explicitly requests separate approval before any user-environment changes or live desktop smoke checks.

## Answer

ProcDeck v0.1 is complete and repository-verified. The repository now includes
an MIT license, and the README records the implemented status, exact-owner
destructive-action boundary, and the distinction between repository checks and
the pending live desktop smoke matrix.

Verification on 2026-09-04:

- `node tests/model.test.js`: 16/16 behavior checks passed.
- `node --test`: passed.
- `omarchy plugin validate .`: passed with Omarchy 4.0.2-1.
- `qmlformat ProcDeck.qml`: parsed successfully.
- `qmllint -I /usr/share/omarchy/shell -I /usr/lib/qt6/qml ProcDeck.qml`:
  passed with Quickshell 0.3.1 and Hyprland 0.56.2 installed.
- `git diff --check`: passed.
- A repository file audit found no package manager, build system, daemon,
  helper executable, install hook, settings subsystem, resource metrics,
  independent palette, marketplace files, or speculative component hierarchy.

No development symlink was created, and the plugin was not enabled, rescanned,
toggled, or smoke-tested in the live desktop. Separate approval is required
before making those user-environment changes or running the manual smoke matrix.
