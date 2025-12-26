# NL Devices Setup - Project Guidelines

## Project Overview

Cross-platform device configuration and optimization toolkit for low-latency audio/video production environments. Targets Windows, Linux, and Mikrotik devices with automated setup via SSH/API.

## Architecture (SOTA 2025)

```
nldevicessetup/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml              # Main CI pipeline
│   │   ├── release.yml         # Automated releases
│   │   └── security.yml        # Security scanning
│   └── CODEOWNERS
├── scripts/
│   ├── bootstrap/
│   │   ├── install.sh          # curl -sSL | bash entry point
│   │   └── install.ps1         # iwr/irm entry point for Windows
│   ├── linux/
│   │   ├── optimize.sh         # Main Linux optimizer
│   │   ├── network.sh          # Network stack tuning
│   │   ├── latency.sh          # Low-latency kernel params
│   │   └── modules/            # Modular optimization scripts
│   ├── windows/
│   │   ├── optimize.ps1        # Main Windows optimizer
│   │   ├── network.ps1         # Network tuning (Nagle, etc)
│   │   ├── latency.ps1         # Timer resolution, MMCSS
│   │   └── modules/            # Modular PowerShell modules
│   └── mikrotik/
│       ├── optimize.rsc        # RouterOS script
│       └── qos.rsc             # QoS configuration
├── lib/
│   ├── common.sh               # Shared bash functions
│   └── common.ps1              # Shared PowerShell functions
├── tests/
│   ├── unit/                   # Unit tests (bats, Pester)
│   ├── integration/            # Integration tests
│   └── e2e/                    # End-to-end device tests
├── configs/
│   ├── linux/                  # Linux config templates
│   ├── windows/                # Windows registry templates
│   └── mikrotik/               # Mikrotik config templates
├── TARGETS.md                  # LOCAL ONLY - never commit
├── TARGETS.example.md          # Template for targets file
├── CLAUDE.md                   # This file
└── README.md                   # Public documentation
```

## Design Principles

### 1. Idempotent Operations
- All scripts must be safely re-runnable
- Check state before modifying
- Log all changes for rollback capability

### 2. Modular Architecture
- Each optimization category is a separate module
- Modules can be enabled/disabled individually
- Clear dependency declaration between modules

### 3. Single-Target Development Mode
- During development, work on ONE target at a time
- No parallel device execution until thoroughly tested
- Target selection via command-line argument

### 4. Bootstrap Pattern
```bash
# Linux
curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | bash

# Windows (PowerShell)
irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex
```

### 5. Test-Driven Development
- Unit tests for all utility functions
- Integration tests with mock devices
- E2E tests on staging devices before production
- Minimum 80% code coverage target

## Optimization Categories

### Linux Targets
- Kernel parameters (sysctl) for low latency
- Network stack tuning (TCP, UDP buffers)
- IRQ affinity and CPU isolation
- Realtime scheduling priorities
- Filesystem tuning (noatime, etc)

### Windows Targets
- Nagle algorithm disable
- Timer resolution (1ms)
- MMCSS audio priority
- Network adapter offloading settings
- Power plan optimization
- Interrupt moderation

### Mikrotik Targets
- Queue trees for QoS
- Firewall mangle rules
- Connection tracking optimization
- Hardware offloading

## Development Workflow

### Branching Strategy
- `main` - stable, released code
- `develop` - integration branch
- `feature/*` - new features
- `fix/*` - bug fixes
- `release/*` - release preparation

### PR Requirements
- All tests passing
- Code coverage maintained/improved
- At least one approval
- No merge conflicts
- Conventional commit messages

### Release Process
1. Semantic versioning (vX.Y.Z)
2. Automated changelog generation
3. GitHub Releases with artifacts
4. Tag-triggered deployment

## CI/CD Pipeline

### On Every PR
- Lint (shellcheck, PSScriptAnalyzer)
- Unit tests (bats-core, Pester)
- Code coverage (codecov)
- Security scan (trivy, dependency review)

### On Merge to Main
- Integration tests
- Build release artifacts
- Update documentation

### On Tag (vX.Y.Z)
- Create GitHub Release
- Publish release notes
- Update latest pointers

## Security Guidelines

- NEVER commit credentials (TARGETS.md in .gitignore)
- Use SSH keys where possible
- Secrets via GitHub Actions secrets only
- Regular dependency updates (Dependabot)
- SAST scanning on all PRs

## Coding Standards

### Bash
- Use shellcheck for linting
- `set -euo pipefail` in all scripts
- Functions must have local variables
- Quote all variables
- Use `[[` for conditionals

### PowerShell
- Use PSScriptAnalyzer
- Strict mode enabled
- CmdletBinding on all functions
- Proper error handling with try/catch
- Approved verbs only

### Documentation
- README for end users
- Inline comments for complex logic
- CHANGELOG.md for version history
- CONTRIBUTING.md for developers
