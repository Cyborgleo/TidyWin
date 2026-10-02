# Security Policy

## Reporting a vulnerability

Please do not post credentials, private system details, or an unpatched exploit in a public issue. Use GitHub's **Report a vulnerability** option in the repository Security tab if it is available. Otherwise, contact the repository maintainer privately before sharing technical details.

## Safe use

- Review scripts before running them with administrator approval. The scripts are intended for Windows 10 and Windows 11.
- Storage Cleanup's Deep Clean can permanently delete System Restore points, Shadow Copies, and `Windows.old`. Review its prompts carefully.
- Gaming Mode saves a restore snapshot before applying its supported settings. Keep the generated state and NVIDIA profile backup until you are finished with Restore.
- NVIDIA Profile Inspector is an optional third-party executable. TidyWin does not bundle or validate downloaded copies; only use a copy obtained from the upstream project linked in the README.
- Report logs can include Windows build information, device names, file paths, and error details. Review them before attaching them to an issue.

## Scope

TidyWin's scripts do not install a service, schedule a task, or download code. The optional NVIDIA integration invokes a local NVIDIA Profile Inspector executable and imports the local preset after creating a backup.
