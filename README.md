<div align="center">

```
  ########  ####  ########   ##    ##     ##      ##  ####  ##    ##
     ##      ##   ##     ##   ##  ##      ##  ##  ##   ##   ###   ##
     ##      ##   ##     ##    ####       ##  ##  ##   ##   ####  ##
     ##      ##   ##     ##     ##        ##  ##  ##   ##   ## ## ##
     ##      ##   ##     ##     ##        ##  ##  ##   ##   ##  ####
     ##      ##   ##     ##     ##        ##  ##  ##   ##   ##   ###
     ##     ####  ########      ##         ###  ###   ####  ##    ##
```

**Clean, optimize and tweak Windows - safely, transparently, offline.**

![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D4)
![Language](https://img.shields.io/badge/built%20with-Batch%20%2F%20PowerShell-1f6feb)
![Network](https://img.shields.io/badge/network-none-2ea043)

</div>

---

## What is TidyWin?

TidyWin is an open-source toolkit for keeping Windows clean, fast and tidy. It is built as a set of small, independent **modules**. Each one does one job, explains what it will do before it does it, and writes a log of what it did.

The goal is simple: give people the benefit of Windows maintenance and performance tweaking **without** having to trust a mystery `.exe`, copy commands from random forums, or know what every setting means.

Everything is plain script. You can open any file in a text editor and read exactly what it does.

### Principles

- **Safe by default.** The default option never removes anything you could need later. Risky actions are clearly labelled, off by default, and ask for confirmation.
- **Transparent.** Plain `.bat` / PowerShell, commented, no compiled binaries, no obfuscation.
- **Offline.** No network connections, no telemetry, no accounts.
- **Your files stay yours.** Documents, Desktop, Downloads, Pictures, Videos, Music and OneDrive are never touched.
- **Logged.** Every run writes a log you can read afterwards.
- **Tell the truth.** Modules say what they skipped or could not do instead of pretending everything worked.

---

## Modules

| Module | Status | What it does |
|---|---|---|
| [**Storage Cleanup**](#storage-cleanup) | Available | Frees disk space: temp files, caches, shader caches, Recycle Bin, update leftovers, optional restore points |
| Performance Tweaks | Planned | Safe, reversible performance and responsiveness settings |
| Startup and Background Apps | Planned | See and trim what starts with Windows |
| Privacy and Telemetry Settings | Planned | Review and reduce data Windows collects |
| Debloat | Planned | Optionally remove preinstalled apps you do not use |

The planned modules are ideas, not promises. Ideas and suggestions are welcome - open an issue.

---

## Storage Cleanup

`storage-cleanup/TidyWin-StorageCleanup.bat`

Frees disk space in one run. Double-click it, pick a mode, and let it work.

### Quick start

1. Download or clone this repository and **extract it** if it came as a ZIP (the script refuses to run from inside a ZIP).
2. Double-click `TidyWin-StorageCleanup.bat`.
3. Click **Yes** on the Windows administrator prompt.
4. Choose a mode:

| Mode | Best for | What it does |
|---|---|---|
| **1 - Standard Clean** (recommended) | Everyone, any time | Cleans temp files and caches. Keeps your restore points and your previous Windows version. |
| **2 - Deep Clean** | Maximum space | Everything in Standard, **plus** all System Restore points / Shadow Copies and the old `Windows.old` folder. **Cannot be undone.** Asks for confirmation. |
| **3 - Exit** | Changed your mind | Changes nothing. |

> Tip: close your browsers and games first. Files that are in use cannot be deleted.

### What Standard Clean removes

- User temp folder, Windows temp folder, `INetCache` and app `TempState` folders
- Recycle Bin (all drives) - **emptied permanently**
- Shader caches: DirectX, NVIDIA, AMD, Intel (rebuilt automatically by games and apps)
- Browser caches only: Edge, Chrome, Brave, Firefox - never cookies, history, passwords or bookmarks
- Windows Update download cache and Delivery Optimization cache
- Windows Error Reporting files, crash dumps, minidumps and `MEMORY.DMP`
- Windows Disk Cleanup items: thumbnails, setup and upgrade logs and similar leftovers
- Old Windows components, using `DISM /StartComponentCleanup` (never `/ResetBase`)

### What Deep Clean adds

- Every System Restore point and Shadow Copy on the Windows drive
- The previous Windows installation folder (`Windows.old`), if one exists

After a Deep Clean you cannot use System Restore to roll back, or go back to your previous Windows version. Windows creates new restore points on its own afterwards.

### What is never touched

- Documents, Desktop, Downloads, Pictures, Videos, Music, OneDrive
- Installed programs, settings, saved passwords, cookies, browsing history
- Prefetch, the WinSxS folder (only DISM may shrink it), the Windows Installer folder, the hibernation file and the page file

### Safety design

- Only empties folders that are listed in the script. The folders themselves are kept, so Windows permissions stay intact.
- Refuses to empty drive roots, user profile folders, or a `TEMP` variable that does not look like a temp folder.
- Does not follow junctions or symbolic links.
- Never closes your programs. Pauses itself if Windows is installing updates.
- Uses only the real Windows tools: it resets `PATH` and runs from `System32`, so a stray file next to the script cannot be executed with admin rights.
- Makes no network connections.
- Writes a log to `C:\ProgramData\TidyWin\Logs\StorageCleanup_<date>_<time>.log`.

### Command line

```bat
TidyWin-StorageCleanup.bat /standard   :: Standard Clean, no questions asked
TidyWin-StorageCleanup.bat /deep       :: Deep Clean, no questions asked
TidyWin-StorageCleanup.bat /help       :: show help
```

Using `/standard` or `/deep` counts as your confirmation, which makes the script usable from Task Scheduler or other automation.

| Exit code | Meaning |
|---|---|
| 0 | Finished |
| 1 | Unsupported Windows version, or administrator rights were not granted |
| 2 | Cancelled by the user |
| 3 | Started from a temporary folder (for example inside a ZIP) |

### Good to know

- **Emptying the Recycle Bin is permanent**, even in Standard mode.
- **Crash dumps are deleted.** If you are debugging a blue screen, copy them somewhere first.
- If you have no dedicated graphics card, the NVIDIA and AMD steps simply find nothing and move on.
- Each step shows an approximate "freed about N MB" figure. Background activity on the PC adds some noise, so treat it as a guide.
- Results vary: a machine that is already tidy will free very little.

---

## Requirements

- Windows 10 (version 1903 or newer) or Windows 11
- An administrator account (the script asks for permission itself)
- No internet connection, no installation

Tested so far on Windows 11. Reports from other Windows versions are welcome.

---

## Safety and disclaimer

TidyWin is provided **as is**, without warranty. It is written to be conservative, but any tool that deletes files or changes system settings carries some risk.

Before running any module on a machine you care about:

- Read the script. It is short and commented.
- Try it first in a virtual machine or **Windows Sandbox**.
- Make sure you have a backup of anything important.

---

## Contributing

Contributions are welcome, especially:

- Test results on different Windows versions and hardware
- Bug reports (please attach the log file from `C:\ProgramData\TidyWin\Logs`)
- New cleanup locations or tweaks, with a short explanation of why they are safe

Please keep to the principles above: nothing hidden, nothing that touches personal files, and anything risky must be opt-in and clearly labelled.

### Line endings

Batch files must use Windows (CRLF) line endings or labels can break. The repository includes a `.gitattributes` rule for this:

```
*.bat text eol=crlf
```

---

## Repository layout

```
TidyWin/
|-- README.md
|-- .gitattributes
|-- LICENSE
`-- storage-cleanup/
    `-- TidyWin-StorageCleanup.bat
```

---

## License

Add a `LICENSE` file before publishing. The MIT License is a common choice for projects like this.
