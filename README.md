# Splunk UF Installation Packages (v10.2.7)

Install / upgrade scripts and download links for the Splunk Universal Forwarder **10.2.7** (build `c0bff5b0fac3`).

Both scripts install from a **local package file** — no internet access is needed on the target host. Download the installer first, put it in the **same folder** as the script, then run the script.

---

## Before you run anything

**You must edit the script and set your Splunk server.** The repo ships with a placeholder (`10.x.x.x`) that will not work.

### Linux — `install.sh`

Edit the variables block at the top:

```bash
SPLUNK_UF_VERSION_RPM="splunkforwarder-10.2.7-c0bff5b0fac3.x86_64.rpm"
SPLUNK_UF_VERSION_DEB="splunkforwarder-10.2.7-c0bff5b0fac3-linux-amd64.deb"
DEPLOYMENT_SERVER="10.x.x.x"          # <-- CHANGE THIS: IP or DNS name of the Splunk Deployment Server
DEPLOYMENT_PORT="8089"
INSTALL_DIR="/opt"
SPLUNK_TEMPADMINPASS="Password-Change" # <-- CHANGE THIS: used only on fresh install, deleted after start
RECONCILE_CONFIG=1                     # 1 = re-apply deploymentclient.conf even if the version already matches
```

### Windows — `install.bat`

Edit the configuration block:

```bat
set "SPLUNK_MSI=splunkforwarder-10.2.7-c0bff5b0fac3-windows-x64.msi"
set "SPLUNK_SERVER=10.x.x.x"          :: <-- CHANGE THIS: IP or DNS name of the Splunk Deployment Server
set "SPLUNK_DIR=C:\Program Files\SplunkUniversalForwarder"
```

Both a raw IP and a DNS name work, e.g. `10.20.30.40` or `splunk-ds.customer.local`. The management port `8089` must be reachable from the client.

---

## Downloading the package

### Windows — MSI Installer (x64)

```
wget -O splunkforwarder-10.2.7-c0bff5b0fac3-windows-x64.msi "https://download.splunk.com/products/universalforwarder/releases/10.2.7/windows/splunkforwarder-10.2.7-c0bff5b0fac3-windows-x64.msi"
```

### Linux — Debian / Ubuntu

```
wget -O splunkforwarder-10.2.7-c0bff5b0fac3-linux-amd64.deb "https://download.splunk.com/products/universalforwarder/releases/10.2.7/linux/splunkforwarder-10.2.7-c0bff5b0fac3-linux-amd64.deb"
```

### Linux — RHEL / CentOS / Rocky

```
wget -O splunkforwarder-10.2.7-c0bff5b0fac3.x86_64.rpm "https://download.splunk.com/products/universalforwarder/releases/10.2.7/linux/splunkforwarder-10.2.7-c0bff5b0fac3.x86_64.rpm"
```

---

## Running the installer

### Linux

The script loses its permission bit when downloaded or copied over SCP/WinSCP, so **you have to make it executable first**:

```bash
chmod +x install.sh
sudo ./install.sh
```

Must be run as **root**. The script auto-detects `dpkg` vs `rpm` and picks the matching package from its own directory. Output is written to both the console and `/var/log/splunkuf-install.log`.

If you edited the file on Windows, strip the CRLF line endings or Bash will fail with `bad interpreter`:

```bash
sed -i 's/\r$//' install.sh
```

### Windows

Right-click `install.bat` → **Run as administrator**, or from an elevated `cmd`:

```bat
install.bat
```

The MSI log is written to `install_log.txt` in the working directory.

---

