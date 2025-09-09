# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of MirrorCalibration seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### Where to Report

Please report security vulnerabilities by emailing the maintainers directly or by opening a private security advisory on GitHub.

**Please do not report security vulnerabilities through public GitHub issues.**

### What to Include

When reporting a vulnerability, please include:

- A description of the vulnerability
- Steps to reproduce the vulnerability
- Versions affected
- Any potential mitigations you've identified

### Response Timeline

- We will acknowledge receipt of your vulnerability report within 48 hours
- We will provide a detailed response within 7 days indicating next steps
- We will notify you when the vulnerability has been fixed

## Security Measures

This repository implements several security measures:

### Automated Security Scanning

- **CodeQL Analysis**: Automated code scanning for security vulnerabilities
- **Dependency Scanning**: Regular dependency vulnerability checks via Dependabot
- **Secret Scanning**: Automated scanning for accidentally committed secrets

### Branch Protection

- Pull requests are required for all changes to the main branch
- All CI checks must pass before merging
- External contributors require maintainer review
- Direct pushes to main branch are prevented

### Code Quality

- Automated code formatting checks
- Quality assurance through Aqua.jl
- Test coverage requirements
- Documentation validation

### Dependency Management

- Automated dependency updates via Dependabot
- Security patches are prioritized
- Compatibility testing across Julia versions

## Secure Development Practices

### For Contributors

1. **Keep Dependencies Updated**: Regularly update dependencies and test for compatibility
2. **Follow Secure Coding**: Avoid hardcoding secrets, use secure random number generation
3. **Test Thoroughly**: Include security-relevant test cases
4. **Document Security Considerations**: Note any security implications in PRs

### For Maintainers

1. **Review Carefully**: Pay special attention to security implications in PRs
2. **Validate Dependencies**: Check new dependencies for security issues
3. **Monitor Alerts**: Respond promptly to GitHub security alerts
4. **Keep Secrets Secure**: Use GitHub secrets for sensitive data, never commit secrets

## Security Tools and Configuration

### GitHub Security Features Enabled

- [x] Dependency graph
- [x] Dependabot alerts
- [x] Dependabot security updates
- [x] Code scanning (CodeQL)
- [x] Secret scanning
- [x] Private vulnerability reporting

### Recommended Local Development Tools

- Use `git-secrets` or similar tools to prevent accidental secret commits
- Enable pre-commit hooks for security scanning
- Use Julia's `Pkg.audit()` to check for known vulnerabilities

## Incident Response

In case of a security incident:

1. **Immediate Response**: Assess and contain the impact
2. **Investigation**: Determine root cause and affected systems
3. **Resolution**: Implement and test fixes
4. **Communication**: Notify affected users appropriately
5. **Post-Incident**: Conduct review and improve security measures

## Security Contact

For security-related questions or concerns, contact:
- Repository maintainers via GitHub
- Create a private security advisory for vulnerabilities

This security policy is reviewed and updated regularly to ensure it remains effective and current.