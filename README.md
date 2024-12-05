# WLAN Pi Kernel

This repository contains build scripts and configurations for the **WLAN Pi** custom Linux kernel.

### **Automated Builds with GitHub Actions**

The repository is set up with a GitHub Actions workflow that automatically builds the Debian package whenever changes are pushed to the `add-build-action` branch.

#### **Workflow Details:**

- **Branch:** `add-build-action`
- **Trigger:** Push events to the `add-build-action` branch
- **Workflow Name:** Build WLANPI Kernel for Debian Bookworm
- **Artifacts:** The built `.deb` package is uploaded as an artifact named `wlanpi-kernel-deb-bookworm`

### **Manual Build Instructions**

If you prefer to build the package manually, follow these steps:

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/WLAN-Pi/wlanpi-kernel.git
   cd wlanpi-kernel

