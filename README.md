# TidyWin

TidyWin is a collection of small Windows tools for storage cleanup and gaming setup. Each module explains what it changes and keeps its settings or actions reversible where possible.

> TidyWin is under development. Review the warnings below before running a script, especially Storage Cleanup's Deep Clean option.

## Current modules

| Module | What it does |
| --- | --- |
| **Storage Cleanup** — `modules/storage-cleanup/overflow.bat` | Removes selected temporary files, caches, and Windows leftovers. Standard Clean empties the Recycle Bin. Deep Clean can also delete restore points, shadow copies, and `Windows.old`. |
| **Gaming Mode** — `modules/gaming-mode/afterburner.bat` | Applies a small Windows gaming profile, optionally imports a reversible NVIDIA global profile, and offers a read-only setup report. It is not MSI Afterburner. |

## Requirements

- Windows 10 or Windows 11.
- Built-in Windows PowerShell 5.1.
- Administrator approval for the script launchers and the actions they perform.
- NVIDIA Profile Inspector only if you want the optional NVIDIA settings in Gaming Mode.

**Security note:** Windows 10 reached end of support on October 14, 2025. Use a supported Windows release, or an eligible Extended Security Updates program, to continue receiving security fixes. See [Microsoft's Windows 10 support notice](https://support.microsoft.com/en-us/windows/deployment/updates-lifecycle/windows-10-support-has-ended-on-october-14-2025).

## Quick start

1. Download or clone the repository, then extract it if you downloaded a ZIP.
2. Keep the project folders and their files together. Do not run a module directly from inside a ZIP.
3. Open the module folder and run its `.bat` launcher. Review the menu and warnings before choosing an action.
4. Keep the generated Gaming Mode state and NVIDIA backup files until you are satisfied with the changes.

## Storage Cleanup

Run `modules/storage-cleanup/overflow.bat` and choose a mode:

- **Standard Clean** removes selected temporary files and caches, shader caches, browser cache files, Windows Update download leftovers, error reports, and selected Windows cleanup items. It empties the Recycle Bin on all drives. Close browsers and games first if you want them to release their cache files.
- **Deep Clean** does everything in Standard Clean and can permanently remove all System Restore points and Shadow Copies on the system drive, plus the previous Windows installation folder (`Windows.old`). The script displays a separate confirmation before Deep Clean.

Deep Clean can remove recovery options and cannot be undone. Check that you do not need restore points or the previous Windows installation before continuing. TidyWin does not use DISM `/ResetBase`.

The script keeps the cleanup folders themselves and is designed to skip reparse-point directories. It does not target personal folders such as Documents, Desktop, Downloads, Pictures, Videos, or Music. It writes logs under `%ProgramData%\TidyWin\Logs`.

## Gaming Mode

Run `modules/gaming-mode/afterburner.bat`. The menu provides:

- **Apply Gaming Mode:** saves a snapshot, enables Windows Game Mode for the current account, selects the Windows High Performance power plan if it is available, and disables Enhance Pointer Precision. You can separately choose whether to disable Xbox Game Bar capture and background recording.
- **Restore Saved Settings:** returns supported settings to the snapshot taken before Apply. Restore the active snapshot before applying again.
- **Check Current Setup:** reports snapshot status, selected Windows preferences, the active power plan, NVIDIA adapter and tool availability, and manual gaming checks. It does not change Windows or NVIDIA configuration. It saves a report log under `%LOCALAPPDATA%\TidyWin\GamingMode\Logs`.

Apply and Restore request administrator approval and must run under the same Windows account. Some options—HAGS, per-game GPU selection, monitor refresh rate, and Windows 11 windowed-game optimization—are left for you to review in Windows Settings because support and results vary. Manual choices are not reverted by Restore.

### Optional NVIDIA settings

Gaming Mode can optionally import the included `afterburner-nvidia.nip` preset using NVIDIA Profile Inspector. It first exports a backup of the global NVIDIA profile. The preset sets Power Management Mode to **Prefer maximum performance** and Texture Filtering - Quality to **Quality**. Maximum performance can increase power use, heat, and fan noise. These global settings can affect multiple 3D applications; use per-game profiles for game-specific tuning where possible.

NVIDIA Profile Inspector is a separate community-maintained tool and is not bundled with TidyWin. If you choose to use it, follow the setup in `tools/README.md` and download it from its [upstream project](https://github.com/Orbmu2k/nvidiaProfileInspector). The setup check confirms whether the adapter, executable, and preset are present; it does not inspect live NVIDIA driver values.

### Manual gaming checks

- On a laptop or hybrid-graphics PC, set each game to **High performance** in Windows Graphics settings if you want it to use the discrete GPU.
- Enable NVIDIA Reflex inside supported games. NVIDIA recommends in-game Reflex rather than forcing the driver's Ultra Low Latency option for games that support Reflex.
- Review HAGS only if Windows offers the option for your hardware. Restart after changing it and compare results.
- Set the monitor to its highest supported refresh rate at the chosen resolution.
- On Windows 11, review windowed-game optimizations for DirectX 10/11 games played in windowed or borderless mode.

Do not expect a guaranteed FPS increase. Compare the same game, scene, resolution, and graphics settings before and after. Record average FPS and frame-time or 1% low results when available, and repeat the run a few times.

## Safety and security

- These scripts make system changes locally. TidyWin itself does not download or upload data.
- Storage Cleanup and Gaming Mode require administrator approval for their launchers. Read each prompt; cancel if you are unsure.
- Deep Clean permanently removes recovery data as described above.
- Gaming Mode keeps its saved state and logs under `%LOCALAPPDATA%\TidyWin\GamingMode`. Do not delete the saved NVIDIA `.nip` backup before you have finished using Restore.
- The Gaming Mode launcher runs its bundled PowerShell helper with a process-scoped execution-policy option; it does not change the saved Windows PowerShell execution policy.
- NVIDIA Profile Inspector is third-party software. TidyWin does not include it or verify its downloaded release. Only obtain it from the upstream project if you choose to use that integration.
- Review logs before sharing them; they can contain system details, paths, device names, and error messages.
- The `Docs/TidyWin Script Optimization Research.md` file is draft research, not a safe runbook. The reviewed choices are in `Docs/TidyWin Script Optimization Plan.md`.

For vulnerability reporting, see [SECURITY.md](SECURITY.md).

## Project layout

```text
TidyWin/
├── Docs/
│   ├── TidyWin Script Optimization Plan.md
│   └── TidyWin Script Optimization Research.md
├── modules/
│   ├── storage-cleanup/
│   │   └── overflow.bat
│   └── gaming-mode/
│       ├── afterburner.bat
│       ├── afterburner-helper.ps1
│       └── afterburner-nvidia.nip
├── tools/
│   └── README.md
├── .gitignore
├── README.md
└── SECURITY.md
```

Optional downloads, generated logs, state, and backups are not part of the source tree.

## Possible future work

A graphical Windows Customization tool for supported animation, transparency, color, and taskbar choices is being considered. It is **not included** in the current repository. TidyWin will avoid shell patchers and unsupported tweaks for that feature.

## License

This repository currently has no `LICENSE` file. It is publicly viewable, but no open-source reuse or redistribution license has been selected yet.

## References

- [Microsoft: Windows graphics preferences and windowed-game optimizations](https://support.microsoft.com/en-us/windows/hardware/display-graphics/optimizations-for-windowed-games-in-windows-11)
- [Microsoft: taskbar customization](https://support.microsoft.com/en-us/windows/experience/personalization/customize-the-taskbar-in-windows)
- [Microsoft: changing monitor refresh rate](https://support.microsoft.com/en-us/windows/hardware/display-graphics/change-the-refresh-rate-on-your-monitor-in-windows)
- [NVIDIA: Manage 3D Settings reference](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/3D%20Settings/Manage_3D_Settings_%28reference%29.htm)
- [NVIDIA: Reflex and low-latency settings](https://www.nvidia.com/en-us/geforce/news/reflex-low-latency-platform/)
- [NVIDIA Profile Inspector upstream project](https://github.com/Orbmu2k/nvidiaProfileInspector)
