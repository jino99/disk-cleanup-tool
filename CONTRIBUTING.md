# Contributing

Contributions are welcome. Please follow these guidelines to keep the project consistent.

## Getting Started

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Test on both Windows 10 and Windows 11 if possible
4. Submit a pull request with a clear description of what changed and why

## Guidelines

**Code style**
- Match the existing formatting and comment style
- Section headers use `# ---------------------------------------------------------------------------` in `disk-cleanup.ps1` and `# --- N. Title ---` in `disk-cleanup-intune.ps1`
- Keep functions focused — one responsibility per function

**Testing**
- Always test with `-Mode Analyze` first to verify simulate behavior before testing `Clean`
- Test both as Administrator and as a standard user for the SDE script
- For Intune changes, verify the return string format is preserved: `CleanupFinished;FreedGB:<n>;FinalFreeGB:<n>`

**Adding new cleanup targets**
- Add to the appropriate section (system-level vs per-user profile)
- Mirror the change in both scripts if the target applies to both
- Update the "What It Cleans" table in `README.md`

**Do not**
- Add interactive prompts to `disk-cleanup-intune.ps1` — it must remain fully silent
- Terminate processes in `disk-cleanup-intune.ps1`
- Access personal folders (Documents, Pictures, Desktop) in either script
- Hardcode drive letters — use `$env:SystemDrive`

## Reporting Issues

Open a GitHub issue with:
- Windows version and PowerShell version
- Which script and parameters were used
- The relevant section of the log file
- Expected vs actual behavior
