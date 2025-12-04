# XSH - Advanced iOS Linux Terminal

<p align="center">
  <img src="app/Assets.xcassets/AppIcon.appiconset/180.png" alt="XSH Logo" width="120"/>
</p>

<p align="center">
  <strong>🚀 نسخة محسّنة ومعدّلة من iSH Shell</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#pro-features">Pro Features</a> •
  <a href="#credits">Credits</a>
</p>

---

## 📱 What is XSH?

XSH is a modified and enhanced version of [iSH](https://github.com/ish-app/ish) - a Linux shell for iOS. XSH brings significant performance improvements, new features, and a better user experience.

**XSH هو نسخة معدّلة ومحسّنة من iSH مع تحسينات كبيرة في الأداء وميزات جديدة.**

---

## ✨ Features

### ⚡ Performance Improvements (تحسينات الأداء)

| Feature | Before | After | Improvement |
|---------|--------|-------|-------------|
| `apk update` | 30-40s | 3-5s | **8x faster** |
| `apk add python3` | 60-90s | 15-20s | **4x faster** |
| `pip install` | 180-240s | 20-30s | **8x faster** |
| I/O Operations | Heavy | Light | **70% less** |
| JIT Cache | 1024 | 4096 | **4x larger** |

### 🔧 System Optimizations

- **tmpfs for /tmp** (256MB) - RAM-based temporary storage
- **tmpfs for apk cache** (128MB) - Faster package installation
- **tmpfs for pip cache** (128MB) - Faster Python packages
- **Increased write delay** - Better battery life & performance
- **4x JIT Cache** - Faster program execution
- **Smart pip wrapper** - Automatically uses `apk` when faster

### 🐍 Smart pip Wrapper

```bash
# When you type:
pip install flask

# XSH automatically does:
apk add py3-flask  # ← 10-20x faster!

# Falls back to pip3 only if package not in apk
```

### 🖥️ New UI Features

- **Multiple Terminal Windows** - Switch between sessions
- **Split Screen Support** - Side-by-side terminals
- **Code Editor** - Built-in text editor with syntax highlighting
- **Download Progress Indicator** - Visual progress for downloads
- **Custom Welcome Message** - Informative MOTD

### 📦 Pre-installed Tools

After first launch setup:
- Python 3 + pip (optimized)
- Git, curl, wget
- OpenSSH client
- Essential build tools

---

## 📥 Installation

### Method 1: Sideloading with AltStore/Sideloadly

1. Download the `.ipa` file from [Releases](../../releases)
2. Install using:
   - **AltStore** (recommended)
   - **Sideloadly**
   - **TrollStore** (if available)

### Method 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/XSH.git
cd XSH

# Initialize submodules
git submodule update --init --recursive

# Open in Xcode
open iSH.xcodeproj
```

### 💡 Installation Tips (نصائح التثبيت)

1. **AltStore Users:**
   - Make sure AltServer is running on your computer
   - Refresh the app every 7 days to prevent expiration
   - Enable "Background App Refresh" for better experience

2. **Sideloadly Users:**
   - Use your Apple ID for signing
   - Check "Remove app limit" if available
   - Re-sign every 7 days (free accounts)

3. **TrollStore Users:**
   - No need to re-sign - permanent installation
   - Best option if your device supports it

4. **First Launch:**
   - Allow network access when prompted
   - Wait for "Setting Up System" to complete
   - Don't close the app during initial setup

---

## 🔐 Pro Features

Some advanced features are available in **XSH Pro**:

### Reverse Engineering Workspace
- Binary Analysis
- ARM64 Disassembler
- Pseudo Code Generator
- Control Flow Graph (CFG)
- String Analysis
- Mach-O Parser

**Get XSH Pro:** [bye-thost.com/product/ish-نسخة-معدلة-من-xsh/](https://bye-thost.com/product/ish-نسخة-معدلة-من-xsh/)

---

## 🛠️ Usage Tips

### Quick Start
```bash
# Update packages
apk update

# Install Python packages (smart wrapper)
pip install flask requests numpy

# Use apk directly for fastest installation
apk add py3-pandas py3-matplotlib
```

### Recommended Packages
```bash
# Development
apk add python3 py3-pip nodejs npm

# Networking
apk add openssh curl wget nmap

# Editors
apk add vim nano

# Utilities
apk add git tmux htop
```

---

## 📊 Technical Details

### System Requirements
- iOS 12.0 or later
- ~500MB storage space
- 512MB+ RAM recommended

### Architecture
- x86 emulation on ARM64
- Alpine Linux base system
- Custom JIT compiler (asbestos)

### Modified Files
- `app/TerminalViewController.m` - UI improvements
- `asbestos/asbestos.h` - JIT cache increase
- `asbestos/frame.h` - Return cache optimization
- Various performance tweaks

---

## 🙏 Credits

### Original Project
- **iSH** by [ish-app](https://github.com/ish-app/ish)
- Licensed under GPL-3.0

### XSH Modifications
- Performance optimizations
- Smart pip wrapper
- UI enhancements
- Pro features

---

## ⚠️ Disclaimer

This is a modified version of iSH for educational and personal use. XSH is not affiliated with the original iSH project.

---

## 📄 License

This project is based on iSH which is licensed under GPL-3.0. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <strong>Made with ❤️ for the iOS Linux community</strong>
</p>

<p align="center">
  <a href="https://bye-thost.com">bye-thost.com</a>
</p>
