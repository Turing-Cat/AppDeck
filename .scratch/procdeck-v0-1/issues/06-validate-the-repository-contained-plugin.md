# 06: Validate the repository-contained ProcDeck v0.1 plugin

**What to build:** Deliver a minimal, repository-contained ProcDeck v0.1 implementation whose documented contract, model behavior, plugin metadata, and target-platform compatibility are verified before any user configuration is changed.

**Blocked by:** 03: Focus the Selected App; 04: Gracefully Close the Selected App; 05: Force Kill the Selected App after confirmation.

**Status:** ready-for-agent

- [ ] The repository contains only the required plugin manifest, shell entry component, pure dependency-free model, one Node self-check, product documentation, license, and existing design records.
- [ ] No package manager, build step, daemon, helper executable, install hook, settings subsystem, resource metrics, independent theme palette, marketplace files, or speculative component hierarchy is introduced.
- [ ] The product status records ProcDeck v0.1 as implemented and repository-verified, and destructive-action wording consistently describes exact Hyprland window owners rather than inferred processes.
- [ ] The dependency-free Node self-check passes and covers the acceptance-critical model behavior accumulated by the preceding tickets.
- [ ] Omarchy plugin validation passes against the supported Omarchy 4.0.2 contract.
- [ ] The shell entry component loads without warnings against Quickshell 0.3.1 and Hyprland 0.56.2 APIs.
- [ ] Repository verification does not create a development symlink, enable the plugin, rescan or toggle the user's shell, modify Omarchy or Hyprland configuration, or claim that the desktop smoke matrix has run.
- [ ] The verification report explicitly requests separate approval before any user-environment changes or live desktop smoke checks.
