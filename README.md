# Inception of Things (IoT)

A hands-on introduction to Kubernetes using **K3s** and **Vagrant**, designed to help you understand cluster setup, deployment, and configuration in lightweight virtual machines.

---

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Prerequisites](#-prerequisites)
- [Project Structure](#-project-structure)
- [Parts](#-parts)
  - [Part 1: K3s Cluster Setup](#part-1-k3s-cluster-setup-p1)
  - [Part 2: K3s Single Server](#part-2-k3s-single-server-p2)
- [Usage](#-usage)
- [Troubleshooting](#-troubleshooting)
- [Technical Notes](#-technical-notes)
- [Resources](#-resources)

---

## 🎯 Project Overview

This project demonstrates how to:
- Set up a **K3s Kubernetes cluster** using Vagrant and VirtualBox
- Configure master/worker node architecture
- Deploy applications on K3s
- Manage cluster networking and provisioning

**K3s** is a lightweight, certified Kubernetes distribution designed for IoT, edge computing, and resource-constrained environments.

---

## 🛠 Prerequisites

Before starting, ensure you have the following installed:

| Tool | Version | Purpose |
|------|---------|---------|
| **VirtualBox** | 6.1+ | VM hypervisor |
| **Vagrant** | 2.3+ | VM orchestration |
| **rsync** | (pre-installed on macOS/Linux) | File synchronization |

### Installation Commands

**macOS:**
```bash
brew install --cask virtualbox
brew install --cask vagrant
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y virtualbox vagrant rsync
```

**Windows:**
- Download VirtualBox from [virtualbox.org](https://www.virtualbox.org/)
- Download Vagrant from [vagrantup.com](https://www.vagrantup.com/)

---

## 📁 Project Structure

```
inception-of-things/
├── README.md           # This file
├── p1/                 # Part 1: Multi-node K3s cluster
│   ├── Vagrantfile     # Vagrant configuration (master + worker)
│   ├── configs/        # (optional) Config files
│   └── scripts/
│       ├── common.sh   # Common setup for all nodes
│       ├── master.sh   # K3s server installation
│       └── worker.sh   # K3s agent installation
│
└── p2/                 # Part 2: Single-node K3s server
    ├── Vagrantfile     # Vagrant configuration (single VM)
    ├── configs/        # (optional) Config files
    └── scripts/
        ├── common.sh   # Common setup
        └── k3s_server.sh  # K3s server installation
```

---

## 🚀 Parts

### Part 1: K3s Cluster Setup (`p1/`)

**Goal:** Create a **two-node K3s cluster** with:
- **Master node** (`<login>S`): K3s server (control plane)
- **Worker node** (`<login>SW`): K3s agent (worker)

#### Features
- ✅ Automated cluster bootstrapping
- ✅ Token-based worker node joining via HTTP server
- ✅ Private network (`192.168.56.0/24`)
- ✅ Minimal resource allocation (2 CPUs, 2GB RAM per node)

#### VMs Configuration

| Node | Hostname | IP | Role |
|------|----------|-----|------|
| Master | `mqaosS` | `192.168.56.110` | K3s Server |
| Worker | `mqaosSW` | `192.168.56.111` | K3s Agent |

#### Quick Start

```bash
cd p1
vagrant up
```

#### What Happens:
1. **Master VM** provisions first:
   - Installs K3s server
   - Exports join token via HTTP server (port 8000)
2. **Worker VM** provisions:
   - Downloads token from master
   - Joins cluster as K3s agent

#### Verification

```bash
# SSH into master
vagrant ssh mqaosS

# Check cluster nodes
kubectl get nodes

# Expected output:
# NAME      STATUS   ROLES                  AGE   VERSION
# mqaoss    Ready    control-plane,master   2m    v1.33.6+k3s1
# mqaossw   Ready    <none>                 1m    v1.33.6+k3s1
```

---

### Part 2: K3s Single Server (`p2/`)

**Goal:** Create a **single-node K3s server** for simplified deployments.

#### Features
- ✅ Standalone K3s server (all-in-one)
- ✅ Ready for application deployment
- ✅ Uses `rsync` for file synchronization (no VirtualBox Guest Additions required)

#### VM Configuration

| Node | Hostname | IP | Role |
|------|----------|-----|------|
| Server | `mqaosS` | `192.168.56.110` | K3s Server |

#### Quick Start

```bash
cd p2
vagrant up
```

#### Verification

```bash
# SSH into server
vagrant ssh

# Check node status
kubectl get nodes

# Expected output:
# NAME     STATUS   ROLES                  AGE   VERSION
# mqaoss   Ready    control-plane,master   30s   v1.33.6+k3s1
```

---

## 💻 Usage

### Common Vagrant Commands

```bash
# Start VMs
vagrant up

# SSH into a VM
vagrant ssh [vm_name]

# Stop VMs
vagrant halt

# Restart VMs
vagrant reload

# Reprovision (re-run scripts)
vagrant reload --provision

# Destroy VMs (delete)
vagrant destroy -f

# Check VM status
vagrant status
```

### Customization

Set environment variables before running `vagrant up`:

```bash
# Custom login (changes VM names)
export LOGIN="mylogin"

# Custom box (for different architectures)
export BOX_NAME="bento/ubuntu-22.04-arm64"  # For Apple Silicon
export BOX_NAME="ubuntu/focal64"             # For x86_64

vagrant up
```

---

## 🔧 Troubleshooting

### Issue: Shared Folder Mount Error

**Error:**
```
Vagrant was unable to mount VirtualBox shared folders. 
Filesystem "vboxsf" is not available.
```

**Solution:**
The Vagrantfiles use `rsync` instead of VirtualBox shared folders:
```ruby
config.vm.synced_folder ".", "/vagrant", type: "rsync", rsync__auto: true
```

If you still see this error:
1. Ensure `rsync` is installed
2. Or disable synced folders:
   ```ruby
   config.vm.synced_folder ".", "/vagrant", disabled: true
   ```

---

### Issue: VM Boot Timeout

**Error:**
```
Timed out while waiting for the machine to boot.
```

**Solution:**
Increase boot timeout in Vagrantfile:
```ruby
config.vm.boot_timeout = 600  # 10 minutes
```

---

### Issue: Worker Can't Join Cluster

**Symptoms:**
- Worker shows "connection refused" errors
- Token download fails

**Solution:**
1. Check master HTTP server:
   ```bash
   vagrant ssh mqaosS
   curl localhost:8000/k3s_token
   ```
2. Verify firewall isn't blocking port 8000
3. Reprovision worker:
   ```bash
   vagrant reload mqaosSW --provision
   ```

---

### Issue: Low Memory / Performance

**Solution:**
Increase RAM allocation in Vagrantfile:
```ruby
VM_MEMORY = 4096  # 4GB instead of 2GB
```

---

## 📚 Technical Notes

### Networking
- **NAT (Adapter 1):** Internet access
- **Host-Only (Adapter 2):** Private network for inter-VM communication
- **IP Range:** `192.168.56.0/24`

### K3s Installation
- Uses official K3s install script: `https://get.k3s.io`
- Installs `kubectl` as symlink: `/usr/local/bin/kubectl -> k3s`
- Server runs as systemd service: `k3s.service`

### Security
- K3s server token stored at: `/var/lib/rancher/k3s/server/node-token`
- Kubeconfig permissions: `644` (world-readable for demo purposes)
- **Production:** Use proper RBAC and token management

### Box Choice
- **Apple Silicon (M1/M2):** Use ARM64 boxes (`cloud-image/ubuntu-20.04`, `bento/ubuntu-22.04-arm64`)
- **Intel/AMD (x86_64):** Use AMD64 boxes (`ubuntu/focal64`, `generic/ubuntu2004`)

---

## 📖 Resources

- [K3s Documentation](https://docs.k3s.io/)
- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- [VirtualBox Manual](https://www.virtualbox.org/manual/)

---

## 👤 Author

**Login:** `mqaos`

---

## 📝 License

This project is for educational purposes as part of the 42 curriculum.

---

**Happy Clustering! 🚀**
