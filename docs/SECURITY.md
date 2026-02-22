# Security Guidelines

This document outlines security best practices for the nldevicessetup device management system.

## Sensitive Data Protection

### Device Inventory

The `devices/` directory may contain sensitive information:

- IP addresses of internal devices
- Hostnames that reveal network topology
- SSH usernames

**Options for protecting this data:**

1. **Keep devices/ in Git (default)** - Suitable for private repositories
2. **Gitignore devices/** - Uncomment in `.gitignore` for extra security
3. **Separate private repository** - Keep devices/ in a separate private repo

### SSH Authentication

**Required:**

- Use SSH key authentication only
- Never store passwords in configuration files
- SSH keys should be stored securely (e.g., `~/.ssh/` with proper permissions)

**Recommended:**

- Use `ssh-agent` for key management
- Consider hardware security keys for critical infrastructure
- Rotate SSH keys periodically

### Secrets Management

For any secrets that need to be stored in the repository:

1. **Use SOPS with age encryption:**

   ```bash
   # Install sops and age
   brew install sops age  # macOS
   sudo apt install sops age  # Ubuntu

   # Generate age key
   age-keygen -o ~/.config/sops/age/keys.txt

   # Create encrypted file
   sops --encrypt --age $(cat ~/.config/sops/age/keys.txt | grep "public key" | cut -d: -f2 | tr -d ' ') secrets.yaml > secrets.sops.yaml
   ```

2. **Environment variables** - Store secrets in environment variables, not in files

3. **GitHub Actions Secrets** - Use repository secrets for CI/CD

## Repository Security

### Branch Protection

The `main` branch should have the following protections:

- Require pull request reviews
- Require status checks to pass
- Require branches to be up to date
- Include administrators in restrictions

### Code Signing

Consider signing commits with GPG:

```bash
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_GPG_KEY_ID
```

## Network Security

### SSH Hardening on Target Devices

Recipes should configure SSH securely:

- Disable password authentication
- Use fail2ban or similar
- Configure firewall rules
- Use non-standard ports if appropriate

### Firewall Considerations

When disabling firewalls for audio/video traffic:

- Document the security implications
- Consider using QoS instead of disabling firewall
- Ensure physical network security
- Use VLANs for isolation

## Audit Trail

The Git-based tracking provides a complete audit trail:

- Every change is recorded with timestamp
- Execution history shows who did what
- State files show current configuration
- `git blame` shows who made each change

## Incident Response

If a security incident occurs:

1. **Contain** - Disable SSH access to affected devices
2. **Assess** - Review `devices/<hostname>/history/` for recent changes
3. **Recover** - Use `git revert` to rollback to known-good state
4. **Document** - Record incident details and remediation steps

## Checklist

Before deploying to production:

- [ ] Repository is private (if devices/ contains sensitive data)
- [ ] SSH keys are properly secured
- [ ] No passwords in configuration files
- [ ] No API keys or tokens in repository
- [ ] Branch protection enabled on main
- [ ] CI/CD passes all security checks
- [ ] Secrets are encrypted or in environment variables
