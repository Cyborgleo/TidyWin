# **Comprehensive Systems Engineering Analysis and Optimization Framework for TidyWin**

> **Draft research only — not an implementation checklist or safe runbook.** This report includes proposals such as driver-package deletion, DISM `/ResetBase`, forced HAGS/MMCSS/network registry values, power-policy changes, and global NVIDIA overrides. Those ideas have not been validated for general use and are intentionally excluded from the current scripts. Read `TidyWin Script Optimization Plan.md` for the reviewed implementation and decisions. The source list below includes forums, blogs, videos, and other secondary material; it should not be treated as proof that a tweak is supported or beneficial. Current launcher names are `overflow.bat` and `afterburner.bat`.

> A few relevant primary-source corrections: Microsoft's MMCSS documentation says GPU Priority and SFIO Priority are not used, and that Priority is treated as 2 for a High scheduling category ([Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)). Microsoft warns that `/ResetBase` prevents uninstalling already-installed updates ([Microsoft Learn](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11)). NVIDIA documents that global settings apply to 3D applications generally, while NVIDIA Profile Inspector exposes settings that may be experimental, deprecated, driver-specific, or undocumented ([NVIDIA Control Panel Help](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/3D%20Settings/Manage_3D_Settings_%28reference%29.htm), [NVIDIA Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector)).

## **Forensic Assessment of Existing TidyWin Automation Suite**

Automated batch scripting for Microsoft Windows environments requires a delicate balance between system stability, resource reclamation, and operational performance. The existing implementation of the TidyWin framework consists of two core scripts: overflow.bat and afterburner.bat. A forensic evaluation reveals that while both scripts incorporate defensive safety checks, their functional scopes can be expanded to achieve maximum disk yield and system responsiveness without compromising operating system integrity.

### **Storage Cleanup Script Evaluation**

The current storage cleanup script operates across two execution tiers: Standard Clean and Deep Clean. It uses an administrative elevation check and applies path validation logic to restrict operations to pre-designated directories, explicitly preventing folder-traversal or junction-following vulnerabilities.  
In Standard Clean mode, the script executes a structured sequence targeting non-essential system caches. It begins by validating path structures across user and system temporary folders, including %TEMP%, %LOCALAPPDATA%\\Temp, system temporary directories, Internet cache (INetCache), and app-package TempState folders. It then empties the system Recycle Bin, strips DirectX, NVIDIA, AMD, and Intel GPU shader caches, and purges browser cache folders across Chromium (Edge, Chrome, Brave) and Gecko (Firefox) profile trees without impacting saved user credentials or history logs.  
For Windows servicing maintenance, the script attempts to stop the Windows Update (wuauserv) and Background Intelligent Transfer Service (bits) to clear update download packages and Delivery Optimization caches1. It removes Windows Error Reporting (WER) archives, crash dumps, and system crash logs (MEMORY.DMP), before executing Windows Disk Cleanup (cleanmgr.exe) via temporary registry flags. Finally, it invokes the Deployment Image Servicing and Management utility (dism.exe /Online /Cleanup-Image /StartComponentCleanup) to clean superseded servicing components while intentionally omitting the irreversible /ResetBase flag3.  
Deep Clean mode introduces two permanent actions: the purge of all Volume Shadow Copies and System Restore checkpoints using vssadmin delete shadows, and the selection of the Previous Windows Installations category to remove Windows.old.  
While these mechanisms are safe, the storage script omits several high-yield, native maintenance functions. Specifically, it does not leverage native Windows transparent file compression via the Windows Overlay Filter (WOF) API or CompactOS4. Furthermore, its update cache clearing relies on basic file deletion rather than structured service resetting and complete Delivery Optimization cache flushing via native PowerShell cmdlets1.

### **Gaming Mode Script Evaluation**

The gaming optimization script utilizes a modular architecture composed of a batch command interface, an elevated PowerShell execution helper, and an optional NVIDIA Profile Inspector configuration file (.nip)6.  
The execution flow begins by validating administrative elevation and account tokens, after which it captures a full configuration restore snapshot under %LOCALAPPDATA%\\TidyWin\\GamingMode. Once state isolation is established, the script attempts to locate and activate the Windows High Performance power scheme via powercfg. If the High Performance scheme is unavailable, it opens the Windows Power settings control panel for manual selection.  
For registry modifications, the script sets AutoGameModeEnabled to 1 under the active user hive, disables pointer acceleration by resetting MouseSpeed, MouseThreshold1, and MouseThreshold2 to 0, and conditionally suppresses GameDVR background video recording by setting GameDVR\_Enabled and AppCaptureEnabled to 08.  
When an NVIDIA GPU and NVIDIA Profile Inspector are present, the script backs up the global driver profile and imports the bundled .nip file6. This file forces two specific driver parameters: Power Management Mode is set to Prefer maximum performance, and Texture Filtering Quality is set to Quality6. The script verifies successful profile application by exporting the active configuration and checking the power flag; if verification fails, it reverts to the backup profile6. Finally, the script launches Windows Graphics settings, leaving hardware-accelerated GPU scheduling (HAGS), variable refresh rate, and display timings untouched for user review.  
The restoration routine relies on the saved configuration snapshot to re-apply the original power scheme, pointer settings, Game Mode state, capture toggles, and NVIDIA driver profiles.  
While safe and fully reversible, the current performance script leaves several low-latency kernel and network scheduling mechanisms unconfigured. Thread priority allocation, Multimedia Class Scheduler Service (MMCSS) task flags, memory executive paging policies, and network acknowledgement frequencies remain at default desktop values8.

## **Architectural Blueprint for Safe Storage Reclamation and Space Optimization**

An enterprise-grade storage cleanup routine must maximize recovered capacity on solid-state drives (SSDs) and NVMe storage devices without damaging operating system binaries, breaking application dependencies, or invalidating system restore mechanisms unnecessarily.

### **Safe Space Recovery Operations**

Expanding the cleanup routine requires targeting non-essential system caches, staging directories, and temporary update repositories through a structured pipeline:

> 1. **SoftwareDistribution Cache Reset**: Stopping the Windows Update (wuauserv) and Background Intelligent Transfer Service (bits) allows safe deletion of all staged update installers located within %windir%\\SoftwareDistribution\\Download1. The download database metadata in %windir%\\SoftwareDistribution\\DataStore can be preserved during routine cleanups to maintain update history logs, or cleared during troubleshooting cycles12.  
> 2. **Delivery Optimization Storage Flush**: Delivery Optimization retains peer-to-peer patch blocks in hidden cache structures. Running the native PowerShell command Delete-DeliveryOptimizationCache \-Force reclaims this space safely without disrupting core Windows services2.  
> 3. **Driver Store Staging Cleanup**: Old driver installation packages linger in the system driver repository after hardware updates. Utilizing pnputil.exe /delete-driver within an automated loop targeting orphaned INF files strips multi-gigabyte driver backups without impacting active device drivers.  
> 4. **Installer Staging and Reset Directories**: Directories such as C:\\\$WINDOWS.\~BT, C:\\\$SysReset, and temporary setup folders left behind by major OS feature updates can be removed once the OS build is validated as stable.

### **Component Store Servicing and Maintenance**

The Windows Component Store (WinSxS) maintains servicing files, side-by-side assembly manifests, and update payloads3. Direct manual deletion of files inside C:\\Windows\\WinSxS causes catastrophic system corruption and must never be attempted. Instead, administrative scripts must interact with WinSxS strictly through the Deployment Image Servicing and Management (DISM) executable3.

| Maintenance Level | Command Syntax | System Effect | Reversibility / Trade-off |
| :---- | :---- | :---- | :---- |
| Standard Component Cleanup | dism.exe /Online /Cleanup-Image /StartComponentCleanup | Scans for superseded update components and removes files no longer needed by the OS3. | Safe. Preserves update rollbacks if required3. |
| Deep Component Cleanup | dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Removes all superseded versions of every component in the store3. | Irreversible. Reclaims substantial disk space but prevents uninstalling current updates3. |
| OS Image Health Repair | dism.exe /Online /Cleanup-Image /RestoreHealth | Verifies component store integrity against official Windows Update manifests. | Highly recommended pre-cleanup step to ensure component consistency. |

### **Modern Windows Transparent File Compression**

For drives constrained by capacity, traditional file deletion can be supplemented by kernel-level transparent filesystem compression. Introduced in Windows 10, the Windows Overlay Filter (WOF) driver allows files to be compressed on disk using modern algorithms and decompressed on-the-fly by the Windows NT kernel with minimal CPU overhead4. When an application or game requests assets from the filesystem, WOF.sys intercepts the read request, decompresses the required blocks in CPU memory at bus speeds, and delivers the uncompressed data directly to RAM or VRAM4. On modern multi-core processors, this pipeline can actually reduce game load times by decreasing physical drive read bottlenecks4.  
Executing compact.exe /CompactOS:always compresses operating system binaries using highly optimized LZX/XPRESS compression schemes4. This yields 2 GB to 5 GB of free space on C: drives without degrading system boot times on SSDs5. The operation is non-destructive and can be reverted using compact.exe /CompactOS:never5. Similarly, games containing uncompressed asset archives benefit significantly from transparent compression4. Utilizing compact.exe with WOF algorithms compresses read-heavy directories without altering folder structures or breaking game executables4.

| Compression Algorithm | Compression Ratio | CPU Overhead | Recommended Use Case |
| :---- | :---- | :---- | :---- |
| XPRESS4K | Low (15% – 25%)4 | Extremely Low14 | Ultra-fast execution; older legacy dual-core CPUs14. |
| XPRESS8K | Moderate (25% – 35%)15 | Very Low14 | Default balanced mode for standard desktop applications15. |
| XPRESS16K | High (35% – 50%)4 | Low14 | Modern multi-core gaming systems; fast SSD load times4. |
| LZX | Maximum (40% – 60%)4 | Moderate14 | Static game folders, archival software, non-write-heavy directories4. |

### **Comprehensive Storage Action and Safety Matrix**

The following matrix details targeted storage locations, execution safety parameters, and expected space yields across modern Windows installations.

| Target Category | Specific Directory / Command | Default Action | Safety Level | Potential Yield | System Impact / Notes |
| :---- | :---- | :---- | :---- | :---- | :---- |
| User Temp Data | %TEMP%, %LOCALAPPDATA%\\Temp | Purge contents | Completely Safe | 1 GB – 10 GB | Deletes transient application data. Skip files locked by running processes. |
| System Temp Data | %windir%\\Temp, %windir%\\SystemTemp | Purge contents | Completely Safe | 500 MB – 5 GB | Administrative privileges required. Locked files auto-skipped. |
| Windows Update Cache | %windir%\\SoftwareDistribution\\Download | Purge contents | Completely Safe | 2 GB – 15 GB | Requires stopping wuauserv and bits prior to directory wipe1. |
| Delivery Optimization | Delete-DeliveryOptimizationCache \-Force | PowerShell Cmdlet | Completely Safe | 1 GB – 10 GB | Clears peer-to-peer update distribution staging cache2. |
| Browser Caches | Chromium & Firefox Profile Cache directories | Purge contents | Completely Safe | 1 GB – 8 GB | Targets temporary web images/scripts. Retains cookies, history, and log-ins. |
| Shader Caches | DirectX, Vulkan, NVIDIA, AMD, Intel Cache | Purge contents | Completely Safe | 500 MB – 4 GB | Forces drivers/games to rebuild caches; may cause brief initial stutter in games. |
| Error Logs & Dumps | %windir%\\Memory.dmp, WER Archives, Minidumps | Purge contents | Safe (Diagnostic Loss) | 1 GB – 16 GB | Removes diagnostic crash dumps. Safe unless troubleshooting active BSODs. |
| OS Binaries (CompactOS) | compact.exe /CompactOS:always | System Compression | Completely Safe | 2 GB – 5 GB | Transparently compresses system binaries via kernel WOF driver4. |
| Component Store | DISM /Online /Cleanup-Image /StartComponentCleanup | DISM Servicing | Completely Safe | 1 GB – 6 GB | Removes superseded update components without breaking rollback capability3. |
| System Hibernation | powercfg /hibernate off | Disable Service | Safe (Tweak) | Equal to RAM (8–32GB) | Disables Windows Fast Startup and Hibernation; reclaims hiberfil.sys. |
| Shadow Copies | vssadmin delete shadows /for=C: /all /quiet | Delete VSS | High Risk | 5 GB – 50 GB | Destroys all System Restore points and previous file versions. Use cautiously. |

### **Strict Exclusion Policy for Critical Directories**

To avoid causing operating system instability, unbootable states, or loss of critical user data, cleanup scripts must explicitly exclude specific paths:

* **C:\\Windows\\Prefetch**: The Prefetch directory contains boot and application launch tracing logs used by the Windows SysMain service to optimize storage indexing18. Deleting Prefetch files provides zero long-term space savings, forces Windows to rebuild launch maps, and temporarily increases application load times and CPU disk thrashing18.  
* **C:\\Windows\\System32 and C:\\Windows\\WinSxS**: Direct file system deletion inside these directories corrupts Windows file signatures and system file integrity verification checks.  
* **Pagefile and Swapfile (pagefile.sys, swapfile.sys)**: Virtual memory paging files managed dynamically by the Windows Memory Manager must never be deleted manually.  
* **User Profile Shell Folders**: Documents, Desktop, Downloads, Pictures, Videos, and OneDrive synchronization points must remain untouched by automated cleanup scripts.

## **High-Performance Gaming Optimization Engine**

Optimizing Microsoft Windows for high-performance gaming requires low-level kernel adjustments that prioritize foreground thread scheduling, reduce micro-stutters, minimize input processing delay, and prevent power-throttling states across hardware components8.

### **Power Subsystem and CPU Core Parking Automation**

Standard Windows power profiles aggressively throttle CPU frequencies and park processor cores during brief idle states to lower thermal output. For gaming workloads, CPU core unparking and instantaneous clock ramp-up are essential for smooth frame pacing and preventing 1% low frame-rate drops.

> 1. **Ultimate Performance Power Scheme**: Scripts should query and activate the Windows Ultimate Performance power scheme using powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61. If the scheme is missing (common on modern Windows 11 builds), it should be duplicated from the hidden system template using powercfg \-duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 prior to activation.  
> 2. **Disabling Core Parking and PCIe Link Power**: Advanced power parameters should be configured via powercfg sub-commands to ensure CPU cores remain active and PCI Express Link State Power Management (ASPM) is forced to Off, preventing GPU latency spikes caused by PCIe power state transitions.

### **Kernel Thread Scheduling and Foreground Priority (Win32PrioritySeparation)**

The Windows NT kernel allocates CPU execution time to threads based on a quantum allocation mask defined in the system registry9. The key Win32PrioritySeparation, located at HKLM\\SYSTEM\\CurrentControlSet\\Control\\PriorityControl, dictates how the processor scheduler balances foreground application focus against background tasks9.  
The value is evaluated as a 6-bit mask:

* **Bits 5–4**: Quantum Length (Short 01 vs. Long 10).  
* **Bits 3–2**: Quantum Variance (Variable 01 vs. Fixed 10).  
* **Bits 1–0**: Foreground Boost Ratio (None 00, Moderate 01, Maximum 10).

The optimal configuration for general gaming workloads on desktop Windows is 0x26 (38 decimal), representing binary 001001109. This setting enforces short quanta lengths, variable quantum intervals, and a maximum priority boost to the active foreground application window9. As a result, the active game engine thread receives immediate, uninterrupted CPU scheduling priority over background processes8. If micro-stutters occur on specific asymmetric core architectures, 0x2A (42 decimal—short quantum, fixed length, maximum boost) serves as a stable alternative8.

### **Multimedia Class Scheduler Service (MMCSS) Configuration**

The Multimedia Class Scheduler Service (MMCSS) enables multimedia applications—including game engines—to claim prioritized access to CPU and GPU resources during real-time processing24. MMCSS configuration is controlled via registry keys under HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile8.  
Within the global SystemProfile subkey:

* SystemResponsiveness: Controls the percentage of CPU execution time reserved for low-priority background tasks8. The Windows default value is 20 (20%)24. Setting this value to 10 (10%) ensures that 90% of system resources are strictly reserved for the foreground game, balancing background safety with low-latency performance8. Setting SystemResponsiveness to 0 can introduce audio thread starvation or scheduler conflicts on modern multi-core processors and should be avoided24.  
* NetworkThrottlingIndex: Throttles non-interactive network traffic when processing multimedia streams8. Setting NetworkThrottlingIndex to ffffffff (hexadecimal) completely disables network throttling, allowing network adapters to process packet bursts without latency penalties8.

Within the Tasks\\Games subkey, parameters dictate scheduling flags when a binary registers itself as a game workload8:

* GPU Priority set to 8 (maximum priority in the DWM/GPU scheduling queue)8.  
* Priority set to 6 (elevates game thread priority above standard software)8.  
* Scheduling Category set to High8.  
* SFIO Priority set to High (prioritizes game file read/write operations on disk)8.

### **Memory Subsystem Optimization and the SysMain (Superfetch) Analysis**

Managing virtual memory behavior is crucial for preventing stutter during asset streaming.

> 1. **Disabling Paging Executive (DisablePagingExecutive)**: Located at HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Memory Management, setting DisablePagingExecutive to 1 forces the Windows NT kernel to retain executive drivers and system code in physical RAM rather than paging them out to the virtual memory pagefile on disk8. This parameter requires 16 GB or more of system RAM and reduces latency when alt-tabbing or requesting system calls during gameplay8.  
> 2. **Analysis of SysMain (Superfetch)**: The SysMain service preloads frequently used applications into unused system RAM to speed up launch times18.  
   * *Arguments for disabling SysMain*: On systems equipped with high-speed NVMe SSDs, preloading application binaries into RAM yields negligible real-world load time benefits while generating background disk read operations that can cause frame-time spikes in open-world games19.  
   * *Arguments for keeping SysMain enabled*: Disabling SysMain automatically turns off Windows RAM memory compression18. On systems with limited physical RAM (e.g., 8 GB or 16 GB under heavy multitasking), disabling memory compression increases total physical memory usage and may trigger pagefile swapping18.  
   * *Strategic Recommendation*: SysMain should remain enabled by default for universal compatibility, but can be safely set to Manual or Disabled on systems with 32 GB or more of high-speed RAM and dedicated NVMe storage19.

### **Network Stack Latency Optimization**

For competitive online titles utilizing the TCP protocol, Windows applies Nagle's Algorithm by default to combine small network packets into larger frames before transmission, improving bandwidth efficiency at the expense of latency10.  
Nagle's Algorithm can be disabled per network interface within HKLM\\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\\Interfaces\\{NIC-GUID}8:

* TcpAckFrequency set to 1 (forces immediate packet acknowledgement without delay)8.  
* TCPNoDelay set to 1 (disables packet buffering delay entirely)8.

While disabling Nagle's algorithm drops latency in TCP-based online titles (such as certain MMORPGs), modern competitive multi-player games operate almost exclusively over User Datagram Protocol (UDP), which inherently bypasses TCP stack mechanics24. Nevertheless, applying these registry keys improves overall network responsiveness without harming network stability8.

### **Input Pipeline and GameDVR Suppression**

To ensure 1:1 hardware sensor tracking across desktop and game environments, pointer precision acceleration must be suppressed at the registry level within HKCU\\Control Panel\\Mouse8: MouseSpeed \= 0, MouseThreshold1 \= 0, and MouseThreshold2 \= 08.  
The Windows GameDVR subsystem continuously records background video and captures input hooks, consuming CPU cycles and GPU encoder bandwidth20. Complete suppression requires configuring three separate registry paths8:

* HKCU\\System\\GameConfigStore: Set GameDVR\_Enabled to 08.  
* HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\GameDVR: Set AppCaptureEnabled to 0\.  
* HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\GameDVR: Set AllowGameDVR to 0\.

### **Graphics Driver Optimization via NVIDIA Profile Inspector**

Automating GPU driver settings requires precise command-line interactions with driver management interfaces6. The NVIDIA Profile Inspector utility provides command-line flags to import pre-configured .nip profile files silently7. Executing nvidiaProfileInspector.exe \-exportUserNamespaces backup.nip creates a complete backup of active settings before applying changes via nvidiaProfileInspector.exe gaming\_preset.nip6.

| Driver Feature Flag | Target Setting | Internal Value | Performance & Latency Rationale |
| :---- | :---- | :---- | :---- |
| Power Management Mode | Prefer Maximum Performance | PREFERRED\_PSTATE\_PREFER\_MAX | Forces GPU to maintain high performance P-States; eliminates downclocking latency6. |
| Low Latency Mode | Ultra / On | LOW\_LATENCY\_MAX\_RENDERED\_FRAMES\_NONE | Limits render queue frame buffering to zero; significantly reduces input delay6. |
| Texture Filtering \- Quality | Quality / High Quality | TEXTURE\_FILTERING\_QUALITY\_HIGH | Ensures sharp texture sampling; modern GPUs handle high quality filtering with negligible FPS impact6. |
| Threaded Optimization | On | OGL\_THREAD\_CONTROL\_ENABLE | Forces driver to offload CPU execution tasks across multiple available processor cores. |
| Vertical Sync | Force Off | VSYNCMODE\_FORCEOFF | Eliminates V-Sync input lag and display buffer stalling in competitive titles. |

## **System Safety Architecture, Registry Management, and Reversibility Protocol**

Automation scripts that alter operating system configurations must adhere to fail-safe design principles. A script should never apply system modifications without establishing an absolute rollback state6.  
The state isolation protocol begins by creating a system restore checkpoint via PowerShell (Checkpoint-Computer \-Description 'TidyWin\_State\_Backup' \-RestorePointType 'MODIFY\_SETTINGS'). Simultaneously, targeted registry keys are exported to %LOCALAPPDATA%\\TidyWin\\Backups using reg.exe export commands. NVIDIA driver states are serialized via Profile Inspector CLI export flags6.  
Only after these backup assets are validated on disk does the script proceed with system modifications. If an error occurs or the user requests a restore, the recovery engine re-imports the saved .reg files, re-applies the original power scheme GUID, re-imports the backup .nip driver profile, and returns the operating system to its baseline configuration. All actions are written to an execution log under %ProgramData%\\TidyWin\\Logs.

## **Technical Recommendations and Strategic Synthesis**

To synthesize the research findings into an actionable engineering blueprint, the ideal implementation structure for the TidyWin optimization suite is detailed below.

### **Master Execution Blueprint for Storage Cleanup (Storage-Cleanup.bat)**

> 1. **Privilege & Path Validation**: Verify administrative token elevation. Ensure execution context is locked to system environment paths, explicitly denying path traversal or root-drive targets.  
> 2. **Standard Non-Destructive Cleanup**:  
   * Stop wuauserv and bits services1.  
   * Purge %TEMP%, %LOCALAPPDATA%\\Temp, %windir%\\Temp, and browser profile caches1.  
   * Clear GPU DirectX/Vulkan/NVIDIA/AMD/Intel shader caches.  
   * Purge update download staging in %windir%\\SoftwareDistribution\\Download1.  
   * Execute PowerShell Delete-DeliveryOptimizationCache \-Force2.  
   * Purge Windows Error Reporting (WER) and memory dump files (MEMORY.DMP).  
   * Restart stopped Windows services1.  
> 3. **Advanced Servicing & Compression (User Selectable)**:  
   * Execute DISM servicing: dism.exe /Online /Cleanup-Image /StartComponentCleanup3.  
   * Query CompactOS state and apply transparent OS compression: compact.exe /CompactOS:always5.  
   * Offer selective folder compression for static games using WOF XPRESS16K or LZX algorithms4.  
> 4. **Deep Clean Safeguards (Optional / Explicit Warning)**:  
   * Prompt user with clear warnings before deleting Volume Shadow Copies (vssadmin delete shadows) or executing DISM with /ResetBase3.  
   * Calculate exact drive space delta before and after execution, logging results to %ProgramData%\\TidyWin\\Logs.

### **Master Execution Blueprint for Gaming Mode (afterburner.bat)**

> 1. **Pre-Flight Snapshot Creation**:  
   * Export active power plan GUID via powercfg /getactivescheme.  
   * Export targeted registry hives (PriorityControl, SystemProfile, Tasks\\Games, Mouse, GameDVR)8.  
   * Export current NVIDIA user driver settings via Profile Inspector CLI6.  
> 2. **Power & Hardware Optimization**:  
   * Duplicate and activate the Ultimate Performance power scheme (e9a42b02-d5df-448d-aa00-03f14749eb61).  
   * Disable CPU Core Parking and PCIe Link State Power Management.  
> 3. **Kernel Scheduling & Network Latency Tuning**:  
   * Apply Win32PrioritySeparation \= 0x26 (DWORD) for optimal foreground application quantum allocation8.  
   * Set DisablePagingExecutive \= 1 (DWORD) to lock kernel drivers into RAM8.  
   * Configure MMCSS Tasks\\Games: GPU Priority \= 8, Priority \= 6, Scheduling Category \= "High", SFIO Priority \= "High"8.  
   * Configure MMCSS SystemProfile: SystemResponsiveness \= 10 (DWORD), NetworkThrottlingIndex \= 0xffffffff (DWORD)8.  
   * Apply Nagle's Algorithm latency fix for active TCP network interfaces (TcpAckFrequency \= 1, TCPNoDelay \= 1\)8.  
> 4. **Input Processing & Display Optimization**:  
   * Enforce raw mouse input by setting MouseSpeed, MouseThreshold1, and MouseThreshold2 to 08.  
   * Suppress GameDVR and background capture policies across HKCU and HKLM hives8.  
> 5. **GPU Driver Configuration**:  
   * Verify NVIDIA Profile Inspector availability6.  
   * Silently import global .nip preset applying Prefer Maximum Performance and Low Latency Mode \= Ultra6.  
> 6. **Restoration Subsystem**:  
   * Provide a one-click restore switch that reads saved registry backups, restores the original power plan GUID, re-imports the original GPU driver profile, and returns the operating system to its baseline configuration.

#### **Works cited**

> 1. Clear Windows Update Cache in Windows 11 & 10 (5 ... \- IObit, [https\://www\.iobit.com/en-blog/clear-windows-update-cache.php](https://www.iobit.com/en-blog/clear-windows-update-cache.php)  
> 2. Windows Update Cache: Why It Grows and How to Clear It Safely, [https\://www\.idiskhome.com/resource/cache/windows-update-cache.shtml](https://www.idiskhome.com/resource/cache/windows-update-cache.shtml)  
> 3. C: Drive filling up rapidly : r/sysadmin \- Reddit, [https\://www\.reddit.com/r/sysadmin/comments/10360ha/c\_drive\_filling\_up\_rapidly/](https://www.reddit.com/r/sysadmin/comments/10360ha/c_drive_filling_up_rapidly/)  
> 4. compactrs \- crates.io: Rust Package Registry, [https\://crates.io/crates/compactrs/2025.12.19](https://crates.io/crates/compactrs/2025.12.19)  
> 5. Is It Safe to Compress the C: Drive to Save Space? \- Cleanor, [https\://cleanor.app/blog/is-it-safe-to-compress-the-c-drive-to-save-space](https://cleanor.app/blog/is-it-safe-to-compress-the-c-drive-to-save-space)  
> 6. Low Latency Gaming – Boost FPS & Reduce Input Lag with MSI, [https\://www\.youtube.com/watch?v=MKZcvWQ8\_9E](https://www.youtube.com/watch?v=MKZcvWQ8_9E)  
> 7. GitHub \- Orbmu2k/nvidiaProfileInspector, [https\://github.com/Orbmu2k/nvidiaProfileInspector](https://github.com/Orbmu2k/nvidiaProfileInspector)  
> 8. Best Windows Registry Tweaks to Gain Competitive Advantage for, [https\://maketecheasier.com/windows-registry-tweaks-for-competitive-gamers/](https://maketecheasier.com/windows-registry-tweaks-for-competitive-gamers/)  
> 9. Processor scheduling and quanta in Windows (and a bit about Unix, [https\://medium.com/@dikrek/processor-scheduling-and-quanta-in-windows-and-a-bit-about-unix-linux-fb5ab02828e2](https://medium.com/@dikrek/processor-scheduling-and-quanta-in-windows-and-a-bit-about-unix-linux-fb5ab02828e2)  
> 10. does reinstalling Windows 10 improve gaming performance, [https\://steamcommunity.com/discussions/forum/11/1484358860937358639/?l=turkish\&ctp=2](https://steamcommunity.com/discussions/forum/11/1484358860937358639/?l=turkish&ctp=2)  
> 11. How to Cleanup the SoftwareDistribution Folder to Fix Windows, [https\://winbuzzer.com/2020/11/12/how-to-delete-the-softwaredistribution-folder-to-fix-windows-update-xcxwbt/](https://winbuzzer.com/2020/11/12/how-to-delete-the-softwaredistribution-folder-to-fix-windows-update-xcxwbt/)  
> 12. manually clearing the WU cache? \- Windows 7 \- Bleeping Computer, [https\://www\.bleepingcomputer.com/forums/t/594088/manually-clearing-the-wu-cache/](https://www.bleepingcomputer.com/forums/t/594088/manually-clearing-the-wu-cache/)  
> 13. The update stuck at 0% is a BITS job, not Windows Update:, [https\://endpointweekly.com/blog/update-stuck-0-percent-bits-transfer-queue-delivery-optimization.html](https://endpointweekly.com/blog/update-stuck-0-percent-bits-transfer-queue-delivery-optimization.html)  
> 14. Win 10 Compact feature: Better Compatible? compression\!, [https\://forum.romexsoftware.com/en-us/viewtopic.php?t=5327](https://forum.romexsoftware.com/en-us/viewtopic.php?t=5327)  
> 15. CompactGUI v2.6.2 \- Free Download \- OlderGeeks.com, [https\://www\.oldergeeks.com/downloads/file.php?id=2250](https://www.oldergeeks.com/downloads/file.php?id=2250)  
> 16. How to Make Room on Your PC via Windows 10 Compression, [https\://wccftech.com/how-to/how-to-compress-windows-10-and-make-some-room-on-your-pc/](https://wccftech.com/how-to/how-to-compress-windows-10-and-make-some-room-on-your-pc/)  
> 17. CompactGUI \- Compress any game with no impact on performance, [https\://www\.reddit.com/r/pcgaming/comments/7787qd/compactgui\_compress\_any\_game\_with\_no\_impact\_on/](https://www.reddit.com/r/pcgaming/comments/7787qd/compactgui_compress_any_game_with_no_impact_on/)  
> 18. Don't disable SysMain (previously known as SuperFetch) : r/computers, [https\://www\.reddit.com/r/computers/comments/c8iq9o/dont\_disable\_sysmain\_previously\_known\_as/](https://www.reddit.com/r/computers/comments/c8iq9o/dont_disable_sysmain_previously_known_as/)  
> 19. Disable superfetch (sysmain) with SSD ? | Tom's Hardware Forum, [https\://forums.tomshardware.com/threads/disable-superfetch-sysmain-with-ssd.3690306/](https://forums.tomshardware.com/threads/disable-superfetch-sysmain-with-ssd.3690306/)  
> 20. Reducing System Overhead: Disabling Background Services ... \- HP, [https\://www\.hp.com/hk-en/tech-takes/gaming/how-to/how-to-optimize-gaming-pc-disable-background-services.html](https://www.hp.com/hk-en/tech-takes/gaming/how-to/how-to-optimize-gaming-pc-disable-background-services.html)  
> 21. Win32PrioritySeparation \- Microsoft Docs | PDF \- Scribd, [https\://www\.scribd.com/document/999082503/Win32PrioritySeparation-Microsoft-Docs](https://www.scribd.com/document/999082503/Win32PrioritySeparation-Microsoft-Docs)  
> 22. Oneclick/Help/Priority Separation Options.md at main \- GitHub, [https\://github.com/QuakedK/Oneclick/blob/main/Help/Priority%20Separation%20Options.md](https://github.com/QuakedK/Oneclick/blob/main/Help/Priority%20Separation%20Options.md)  
> 23. Win32PrioritySeparation for Gaming: 0x26 Explained \- FPSHeaven, [https\://fpsheaven.com/blogs/news/win32priorityseparation](https://fpsheaven.com/blogs/news/win32priorityseparation)  
> 24. Gaming Performance / System Optimization / Tweaks / BF6 \- N1kobg, [https\://n1kobg.blogspot.com/p/blog-page\_23.html](https://n1kobg.blogspot.com/p/blog-page_23.html)  
> 25. 11 Registry Editor tweaks every Windows 11 user needs to know, [https\://www\.xda-developers.com/registry-tweaks-for-windows-11/](https://www.xda-developers.com/registry-tweaks-for-windows-11/)  
> 26. 10 Registry Tweaks for More FPS & Zero Delay \- YouTube, [https\://www\.youtube.com/watch?v=ajdU7xSwJ\_Q](https://www.youtube.com/watch?v=ajdU7xSwJ_Q)  
> 27. Windows 10 registry tweaks \- My Digital Life Forums, [https\://forums.mydigitallife.net/threads/windows-10-registry-tweaks.81346/](https://forums.mydigitallife.net/threads/windows-10-registry-tweaks.81346/)  
> 28. Best Registry Settings for Gaming on Windows 11 \- YouTube, [https\://www\.youtube.com/watch?v=T85Xuj3ZX10](https://www.youtube.com/watch?v=T85Xuj3ZX10)  
> 29. Thoughts on "sysmain" (Prefetch) service being ON or OFF ... \- Reddit, [https\://www\.reddit.com/r/Windows11/comments/15azl3i/thoughts\_on\_sysmain\_prefetch\_service\_being\_on\_or/](https://www.reddit.com/r/Windows11/comments/15azl3i/thoughts_on_sysmain_prefetch_service_being_on_or/)  
> 30. SysMain is Destroying Your PC Performance | Disable it NOW, [https\://www\.youtube.com/watch?v=9qp49SMMzAw](https://www.youtube.com/watch?v=9qp49SMMzAw)  
> 31. Popular Gaming Registry Tweaks: Tested Claims vs. Reality, [https\://windowsoptimize.com/guides/registry-gaming-tweaks-myths-networkthrottling-hpet](https://windowsoptimize.com/guides/registry-gaming-tweaks-myths-networkthrottling-hpet)  
> 32. GitHub \- NRK-git/Escape-From-Low-Frames, [https\://github.com/NRK-git/Escape-From-Low-Frames](https://github.com/NRK-git/Escape-From-Low-Frames)

