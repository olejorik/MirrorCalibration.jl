# MirrorCalibration

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://olejorik.github.io/MirrorCalibration.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://olejorik.github.io/MirrorCalibration.jl/dev/)
[![Build Status](https://github.com/olejorik/MirrorCalibration.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/olejorik/MirrorCalibration.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/olejorik/MirrorCalibration.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/olejorik/MirrorCalibration.jl)
[![Security](https://github.com/olejorik/MirrorCalibration/actions/workflows/security.yml/badge.svg)](https://github.com/olejorik/MirrorCalibration/actions/workflows/security.yml)
[![Code Quality](https://github.com/olejorik/MirrorCalibration/actions/workflows/code-quality.yml/badge.svg)](https://github.com/olejorik/MirrorCalibration/actions/workflows/code-quality.yml)

## Contributing

This repository implements comprehensive branch protection and security measures. Please read our [Security Policy](SECURITY.md) and follow the contribution guidelines below.

### Branch Protection

The main branch is protected with the following requirements:

- **Pull Request Required**: All changes must go through pull requests
- **CI Checks Must Pass**: All automated tests and quality checks must pass
- **Code Review**: External contributors require maintainer review
- **Security Scanning**: Automated security analysis for all code changes
- **Code Quality**: Formatting, linting, and coverage requirements must be met

### Contribution Workflow

1. **Fork and Branch**: Create a feature branch with a descriptive name using prefixes:
   - `feature/` - New features
   - `bugfix/` - Bug fixes  
   - `docs/` - Documentation changes
   - `chore/` - Maintenance tasks

2. **Make Changes**: Follow Julia best practices and maintain test coverage

3. **Test Locally**: Run tests and ensure code quality before pushing

4. **Create PR**: Use conventional commit format for PR titles (e.g., `feat: add new calibration method`)

5. **Wait for Review**: All checks must pass and external contributions require review

### Security

- Security scanning is performed on all code changes
- Report security vulnerabilities through GitHub Security Advisories
- Dependencies are automatically monitored and updated
- See [SECURITY.md](SECURITY.md) for detailed security information
