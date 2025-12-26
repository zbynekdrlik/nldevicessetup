# NL Devices Setup - Target Nodes (Example)

Copy this file to `TARGETS.md` and fill in your actual device information.

**IMPORTANT:** Never commit `TARGETS.md` to version control!

## Active Targets

| Hostname | IP | OS | User | Password | Status |
|---|---|---|---|---|---|
| example-linux | 192.168.1.10 | Linux | admin | changeme | pending |
| example-windows | 192.168.1.20 | Windows | Administrator | changeme | pending |
| example-mikrotik | 192.168.1.1 | Mikrotik | admin | changeme | pending |

## Status Values

- `pending` - Not yet configured
- `configured` - Successfully optimized
- `failed` - Configuration failed (check logs)
- `skip` - Intentionally skipped

## Notes

- Linux targets: SSH access required
- Windows targets: WinRM or SSH required
- Mikrotik targets: API or SSH access required
- Use SSH keys where possible for better security
