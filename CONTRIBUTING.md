# Contributing to MinervaDB-Sysbench

Thank you for your interest in contributing to MinervaDB-Sysbench! This document describes the contribution process, coding standards, and best practices for the enterprise edition.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Contribution Types](#contribution-types)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Commit Message Convention](#commit-message-convention)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Enterprise Support](#enterprise-support)

---

## Code of Conduct

All contributors are expected to follow our Code of Conduct. We are committed to providing a welcoming and professional environment for all contributors regardless of background, identity, or experience level. Harassment, disrespectful language, and unprofessional behavior will not be tolerated.

---

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **sysbench 1.0.20+** installed locally
- **Bash 4.4+** (required for associative arrays in enterprise scripts)
- **jq 1.6+** for JSON processing
- **shellcheck** for shell script linting: `sudo apt install shellcheck` or `brew install shellcheck`
- **Python 3.8+** for result processing scripts
- A **MySQL 5.7+** or **PostgreSQL 12+** instance for integration testing

### Fork & Clone

```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR_USERNAME/MinervaDB-Sysbench.git
cd MinervaDB-Sysbench
git remote add upstream https://github.com/MinervaDB/MinervaDB-Sysbench.git
```

### Set Up Development Environment

```bash
# Install development dependencies (Debian/Ubuntu)
sudo apt-get install -y sysbench jq bc shellcheck python3 python3-pip
pip3 install pyyaml tabulate requests

# Create a dev benchmark profile
cp enterprise/config/profile.template.env enterprise/config/dev.env
# Edit with your local DB settings
vim enterprise/config/dev.env
```

---

## Development Workflow

```
main/master
    |
    +-- feature/your-feature-name
    |       |
    |       +-- (develop, test, push)
    |       |
    |       +-- Pull Request to master
    |
    +-- fix/your-bugfix-name
    |       |
    |       +-- Pull Request to master
```

```bash
# Create a feature branch
git checkout -b feature/add-redis-benchmark

# Make your changes
# ...

# Validate scripts
shellcheck enterprise/scripts/*.sh

# Run basic smoke test
./enterprise/scripts/run_benchmark.sh --profile dev --command prepare --dry-run

# Commit with conventional format (see below)
git add -A
git commit -m "feat(enterprise): add Redis benchmark workload support"

# Push and open PR
git push origin feature/add-redis-benchmark
```

---

## Contribution Types

### Bug Reports

Please include:
- **sysbench version**: `sysbench --version`
- **OS and version**: `cat /etc/os-release`
- **DB type and version**
- **Exact command run** (with password masked)
- **Full error output**
- **Expected vs. actual behavior**

File issues at: https://github.com/MinervaDB/MinervaDB-Sysbench/issues

### Feature Requests

Describe:
- The use case / problem you're solving
- Proposed implementation approach
- Any performance implications
- Whether it's an enterprise-only or general feature

### Code Contributions

We welcome:
- **New workload scripts** (`enterprise/workloads/*.lua`) — custom Lua benchmarks
- **Integration improvements** — new alerting targets, metrics backends
- **Platform support** — new OS/distro compatibility fixes
- **Documentation** — corrections, clarifications, examples
- **Performance improvements** — faster result parsing, lower overhead scripts
- **Security hardening** — improved credential handling, audit logging

---

## Code Standards

### Shell Scripts

All shell scripts in `enterprise/scripts/` must:

1. **Pass shellcheck** with no warnings at severity `warning` or above:
   ```bash
   shellcheck enterprise/scripts/your_script.sh
   ```

2. **Use the standard header pattern**:
   ```bash
   #!/usr/bin/env bash
   # Script description
   # ...
   set -euo pipefail
   ```

3. **Handle all error cases** with meaningful exit codes (0=success, 1=error, 2=SLO violation)

4. **Never log credentials** — always mask passwords in log output:
   ```bash
   # Good
   echo "Connecting to ${DB_HOST} as ${DB_USER}"
   # Bad - never do this
   echo "Password: ${DB_PASSWORD}"
   ```

5. **Use color output conditionally** — only when stdout is a TTY:
   ```bash
   if [[ -t 1 ]]; then RED='\033[0;31m'; else RED=''; fi
   ```

6. **Quote all variable expansions**: `"${VAR}"` not `$VAR`

7. **Use `readonly` for constants** defined at script top

8. **Document all options** in the script header comment block

### Lua Workload Scripts

Custom Lua workloads in `enterprise/workloads/` must:

1. Include a header comment with: purpose, required tables, and connection assumptions
2. Implement the standard sysbench hook functions: `thread_init()`, `event()`
3. Optionally implement: `thread_done()`, `sysbench.hooks.report_intermediate()`
4. Be self-contained or depend only on bundled sysbench Lua modules
5. Not hardcode any connection parameters

### Configuration Files

New configuration parameters added to `profile.template.env` must:

1. Include an inline comment explaining the parameter
2. Show valid values or range
3. Include a sane default value
4. Be grouped logically with related parameters
5. Document any security implications if applicable

### Documentation

- Write in clear, professional English
- Use present tense ("Runs the benchmark" not "This will run")
- Include working code examples for all new features
- Update the Table of Contents in README-ENTERPRISE.md if adding sections
- Document any new environment variables in profile.template.env

---

## Testing Requirements

### Before Submitting a PR

- [ ] All shell scripts pass `shellcheck` with no warnings
- [ ] New features include usage examples in the PR description
- [ ] Configuration changes are reflected in `profile.template.env`
- [ ] README-ENTERPRISE.md is updated if user-facing behavior changes
- [ ] No credentials, passwords, or sensitive data in any committed files
- [ ] The feature works with both MySQL and PostgreSQL if DB-touching

### Integration Testing

If you have access to a test database, please run:

```bash
# Smoke test — quick 30s run
export DB_HOST=localhost DB_USER=sbtest DB_PASSWORD=test DB_NAME=sbtest
./enterprise/scripts/run_benchmark.sh --profile dev --workload oltp_read_write --command prepare
./enterprise/scripts/run_benchmark.sh --profile dev --workload oltp_read_write --time 30 --command run
./enterprise/scripts/run_benchmark.sh --profile dev --workload oltp_read_write --command cleanup
```

Include the (sanitized) output in your PR description.

---

## Commit Message Convention

We follow the **Conventional Commits** specification:

```
<type>(<scope>): <short summary>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `docs` | Documentation only changes |
| `style` | Code style changes (formatting, no logic change) |
| `refactor` | Code restructuring without feature/bug change |
| `perf` | Performance improvements |
| `test` | Adding or fixing tests |
| `ci` | CI/CD pipeline changes |
| `chore` | Maintenance, dependency updates |
| `security` | Security fixes or hardening |

### Scopes

| Scope | Description |
|-------|-------------|
| `enterprise` | Enterprise scripts, config, workloads |
| `docker` | Container/Docker-related changes |
| `ci` | GitHub Actions / CI pipeline |
| `docs` | Documentation files |
| `config` | Configuration templates |
| `core` | Core sysbench source changes |

### Examples

```
feat(enterprise): Add PostgreSQL replication lag workload

fix(enterprise): Fix SLO check for zero-value thresholds

docs(enterprise): Add capacity planning guide to README

ci: Add shellcheck step to GitHub Actions workflow

security(enterprise): Mask database password in debug log output
```

---

## Pull Request Guidelines

### PR Title

Use the same Conventional Commits format as commit messages:
`feat(enterprise): Add Redis benchmark workload support`

### PR Description Template

```markdown
## Summary
Brief description of what this PR does and why.

## Changes
- Added X
- Modified Y
- Fixed Z

## Testing Done
- [ ] shellcheck passed
- [ ] Smoke test run against MySQL X.Y
- [ ] Smoke test run against PostgreSQL X.Y (if applicable)

## Output Sample
(Paste sanitized benchmark output here)

## Breaking Changes
(List any breaking changes, or "None")
```

### Review Process

1. All PRs require at least one review from a repository maintainer
2. CI checks must pass (shellcheck, smoke test if configured)
3. Large features may require a design discussion issue first
4. Breaking changes to the enterprise config schema require a migration guide

---

## Enterprise Support

For enterprise-grade support, custom workload development, production consulting, and priority issue resolution:

- **Website**: https://minervadb.com
- **Email**: info@minervadb.com
- **GitHub Issues**: https://github.com/MinervaDB/MinervaDB-Sysbench/issues

---

*Thank you for contributing to MinervaDB-Sysbench. Your contributions help database teams worldwide run better benchmarks and make more informed performance decisions.*
