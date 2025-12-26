# NL Devices Setup

Cross-platform device configuration and optimization toolkit for low-latency audio/video production environments.

## Features

- **Low-latency optimizations** for Windows and Linux
- **Network stack tuning** (TCP/UDP buffers, congestion control)
- **QoS configuration** for Mikrotik routers
- **One-line installation** via curl/irm
- **Idempotent operations** - safe to re-run
- **Modular architecture** - enable only what you need

## Quick Start

### Linux

```bash
curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | bash
```

Then run optimization:
```bash
sudo nldevicessetup
# or
sudo /opt/nldevicessetup/scripts/linux/optimize.sh
```

### Windows (PowerShell as Administrator)

```powershell
irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex
```

Then run optimization:
```powershell
& "$env:ProgramFiles\nldevicessetup\scripts\windows\optimize.ps1"
```

## What Gets Optimized?

### Linux
- Network buffer sizes (rmem, wmem)
- TCP congestion control (BBR when available)
- Kernel scheduler parameters
- Swap behavior (reduced swappiness)
- Filesystem mount options

### Windows
- Nagle's Algorithm (disabled)
- MMCSS audio/video priority
- Timer resolution (1ms)
- Network adapter settings
- Power plan (High Performance)
- USB selective suspend (disabled)

### Mikrotik (Coming Soon)
- Queue trees for QoS
- Firewall mangle rules
- Connection tracking optimization

## Modules

| Module | Linux | Windows | Description |
|--------|-------|---------|-------------|
| network | Yes | Yes | Network stack tuning |
| latency | Yes | Yes | Low-latency kernel/system params |
| power | No | Yes | Power management |
| filesystem | Yes | No | Mount options, noatime |
| realtime | Yes | No | RT scheduling setup |

Run specific modules:
```bash
# Linux
sudo nldevicessetup --modules network,latency

# Windows
.\optimize.ps1 -Modules network,latency
```

## Dry Run Mode

Preview changes without applying them:

```bash
# Linux
sudo nldevicessetup --dry-run

# Windows
.\optimize.ps1 -DryRun
```

## Target Management

Copy `TARGETS.example.md` to `TARGETS.md` and add your devices:

```markdown
| Hostname | IP | OS | User | Password | Status |
|---|---|---|---|---|---|
| myserver | 10.0.0.10 | Linux | admin | - | pending |
```

**Never commit TARGETS.md** - it contains credentials.

## Development

### Prerequisites
- Bash 4+ (Linux)
- PowerShell 5.1+ (Windows)
- Git

### Running Tests

```bash
# Linux (bats-core)
bats tests/unit/*.bats

# Windows (Pester)
Invoke-Pester -Path tests/unit/
```

### Linting

```bash
# Bash
shellcheck scripts/**/*.sh

# PowerShell
Invoke-ScriptAnalyzer -Path scripts/ -Recurse
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and linting
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Optimizations based on best practices from:
- Linux kernel documentation
- Microsoft performance tuning guides
- Mikrotik RouterOS wiki
- Real-world audio/video production experience
