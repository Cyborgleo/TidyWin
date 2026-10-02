# TidyWin Script Optimization Plan

**Status: implemented safe baseline and read-only setup report, 2026-10-02.** This document supersedes the earlier proposal to apply every tweak listed in the research notes. The research file is a collection of ideas to evaluate, not a runbook. Some suggestions there are unsupported, global, irreversible, or potentially counterproductive; they are deliberately not enabled by TidyWin.

## Current files

- `modules/storage-cleanup/overflow.bat` — storage cleanup module.
- `modules/gaming-mode/afterburner.bat` — interactive launcher for TidyWin Gaming Mode. Despite its filename, it is not MSI Afterburner.
- `modules/gaming-mode/afterburner-helper.ps1` — Windows settings, backup, restore, and optional NVIDIA orchestration.
- `modules/gaming-mode/afterburner-nvidia.nip` — two-setting optional NVIDIA global-profile preset.

The Gaming Mode state and logs remain in `%LOCALAPPDATA%\TidyWin\GamingMode` so earlier `GamingMode-State.json` snapshots remain available to Restore.

## Implemented behavior

### Storage Cleanup

`overflow.bat` retains the reviewed cleanup targets and safety checks documented in the README. Standard Clean removes selected temporary files and caches, empties the Recycle Bin, clears selected update leftovers, and runs Windows component cleanup. Deep Clean additionally removes system restore points/shadow copies and the prior Windows installation when present. These Deep Clean actions can remove recovery options, so the script requires a separate confirmation even for the `/deep` command-line option. It does not use DISM `/ResetBase`, delete driver-store packages, disable hibernation, or change CompactOS.

### Gaming Mode

`afterburner.bat` applies a small, restorable Windows profile: Windows Game Mode, the High Performance power plan if available, and mouse acceleration off. Xbox Game Bar background capture is changed only if the user opts in. Settings are snapshotted before changes, and Restore uses the saved snapshot. A second Apply is blocked until the previous snapshot is restored.

The optional NVIDIA step is skipped unless an NVIDIA GPU and NVIDIA Profile Inspector are available and the profile backup can be made. It backs up the global profile before changing two settings:

- Power management mode: **Prefer maximum performance**. This can raise power use, temperature, and fan noise. The preference applies globally to 3D programs without their own override.
- Texture filtering - Quality: **Quality**, NVIDIA's GeForce default.

The graphics settings page is opened for the user to review HAGS, per-game GPU selection, windowed-game options, and display refresh rate. The script does not force those settings because supported hardware, driver behavior, display configuration, and game results vary.

The menu's **Check Current Setup** action reads the saved Gaming Mode state, selected Windows preferences, active power plan, NVIDIA adapter/tool availability, and the NVIDIA preset file. It does not edit Windows or NVIDIA configuration. It records the report in the existing Gaming Mode log folder and prints manual reminders for per-game GPU selection, monitor refresh rate, Windows 11 windowed-game optimizations, and in-game NVIDIA Reflex. The check detects tool/preset readiness but does not query or modify live NVIDIA driver profile values.

## Deliberately excluded proposals

| Proposal from the draft notes | Decision | Reason |
| --- | --- | --- |
| DISM `/StartComponentCleanup /ResetBase` | Excluded | Microsoft documents that already-installed updates cannot be uninstalled afterward. The regular `/StartComponentCleanup` command is kept without that switch. |
| Automated driver-store / INF deletion | Excluded | Determining that a driver package is safe to delete is device-specific; removing an in-use or needed package can break a device. |
| Forced HAGS registry value | Excluded | Use the supported Windows Settings toggle when the OS exposes it; availability and performance vary by hardware and driver. |
| MMCSS `GPU Priority`, `SFIO Priority`, and high game-priority overrides | Excluded | Microsoft's documentation says GPU Priority is not used, SFIO Priority is not used, and Priority is treated as 2 for a High scheduling category. Registry edits here are not reliable FPS controls. |
| TCP Nagle/ACK, `Win32PrioritySeparation`, `PowerThrottlingOff`, paging-executive, and broad system-profile edits | Excluded | They are not validated as general gaming improvements, can affect the whole PC, and add restore complexity. |
| Global NVIDIA Low Latency Ultra, V-Sync Off, forced Threaded Optimization, or fixed shader-cache size | Excluded | These are not universally optimal and can conflict with game-specific controls, frame pacing, VRR, or driver behavior. Prefer a game's own settings or a per-game driver profile when a measured need exists. |
| Automatic hibernation/CompactOS changes and speculative application-cache/log deletion | Excluded | They can change recovery/power behavior or remove data needed by applications; space recovery and performance effects are system-specific. |
| Building or bundling an optimizer EXE | Excluded | `afterburner.bat` uses Windows PowerShell and an optional separately downloaded NVIDIA Profile Inspector. TidyWin does not need to ship a new binary to apply this limited preset. |

## Verified references

- [Microsoft: DISM component cleanup and `/ResetBase` behavior](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11)
- [Microsoft: MMCSS registry settings and their documented behavior](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)
- [NVIDIA: Manage 3D Settings reference](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/3D%20Settings/Manage_3D_Settings_%28reference%29.htm)
- [NVIDIA Profile Inspector: upstream project and command-line documentation](https://github.com/Orbmu2k/nvidiaProfileInspector)
- [NVIDIA: Reflex and low-latency settings](https://www.nvidia.com/en-us/geforce/news/reflex-low-latency-platform/)
- [Microsoft: Windows 11 graphics preferences and windowed-game optimizations](https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11)

The chosen profile aims for a simple, reversible starting point. It cannot promise a particular FPS gain or one best configuration for every computer and game.
