# Contributing to Encrypted Tiered Storage (ETS)

Thank you for your interest in contributing to **Encrypted Tiered Storage (ETS)**! We welcome contributions, bug fixes, enhancements, and documentation improvements.

---

## 🛠️ Development Environment Setup

### Required Tools

Before submitting changes, ensure you have the following linters and tools installed:

- **Bash 5.0+**
- **ShellCheck** (`v0.9.0+`): Shell script static analysis tool
  ```bash
  # Debian/Ubuntu
  sudo apt-get install -y shellcheck
  ```
- **shfmt** (`v3.6.0+`): Shell script formatter
  ```bash
  # Go install or download prebuilt binary
  go install mvdan.cc/sh/v3/cmd/shfmt@latest
  ```
- **Python 3.10+** (with `textual` for TUI tools)
  ```bash
  pip install --user textual rich
  ```
- **rclone** (`v1.60+`) & **mergerfs** (`v2.33+`)

---

## 🧪 Testing Locally (Without Cloud Credentials)

Never test against production cloud storage or real Telegram bots. You can set up a completely isolated local dummy remote using rclone's `alias` backend:

```bash
# 1. Create a scratch directory
mkdir -p /tmp/dummy_cloud

# 2. Configure a dummy rclone remote
rclone config create dummycloud alias remote /tmp/dummy_cloud

# 3. Create dummy encrypted remote
rclone config create dummycrypt crypt \
    remote dummycloud:encrypted \
    filename_encryption standard \
    directory_name_encryption true \
    password "dummytestpassword123"

# 4. Run dry run validation
./setup.sh --dry-run
```

---

## 📐 Coding Standards & Guidelines

### 1. Bash Scripts (`scripts/*.sh`, `setup.sh`, `test.sh`, `uninstall.sh`)

- Always enforce strict mode at the top of every script:
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  ```
- Ensure systemd user PATH is explicitly set where appropriate:
  ```bash
  export PATH="$HOME/.local/bin:${PATH}"
  ```
- All shell scripts must pass `shellcheck` with zero warnings:
  ```bash
  shellcheck setup.sh test.sh uninstall.sh scripts/*.sh
  ```
- All shell scripts must be formatted with `shfmt` using 4 spaces:
  ```bash
  shfmt -i 4 -w setup.sh test.sh uninstall.sh scripts/*.sh
  ```
- Use `flock` file locking on any non-reentrant sync scripts to prevent race conditions.
- When reading null-delimited outputs in bash, use `while IFS= read -r -d '' var; do`.

### 2. Python Scripts (`scripts/telegram_alert.py`, `scripts/ets-setup`, `scripts/ets-monitor`)

- Keep core notification scripts (`telegram_alert.py`) zero-dependency (using Python standard library `urllib`).
- Terminal UI tools (`ets-setup`, `ets-monitor`) use `textual` and `rich`.
- Ensure scripts pass compilation checks:
  ```bash
  python3 -m py_compile scripts/telegram_alert.py scripts/ets-setup scripts/ets-monitor
  ```

### 3. Systemd Unit Templates (`systemd/*.template`)

- ETS runs strictly **rootless** via `systemctl --user`. Never require root privileges or write to `/etc/systemd/system/`.
- Template variables are wrapped in `{{VARIABLE}}` placeholders and rendered by `setup.sh`.

---

## 🚀 Submitting a Pull Request

1. Fork the repository and create a new feature branch:
   ```bash
   git checkout -b feature/my-feature-name
   ```
2. Commit your changes with clear, descriptive commit messages.
3. Verify formatting and linting locally:
   ```bash
   shfmt -i 4 -d setup.sh test.sh uninstall.sh scripts/*.sh
   shellcheck setup.sh test.sh uninstall.sh scripts/*.sh
   ```
4. Push your branch to your fork and open a Pull Request against `main`.
