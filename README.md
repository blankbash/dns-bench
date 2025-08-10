# DNS Bench (PowerShell)

![Version](https://img.shields.io/badge/version-1.4-blue.svg) ![License](https://img.shields.io/badge/license-GNU%20GPL%20v3-green.svg)

## Overview
`dns-bench.ps1` is a PowerShell script for benchmarking DNS servers.  
It measures **average time**, **median**, **P95**, **minimum**, and **maximum** response times for a given list of domains, repeating the queries for each configured server.  

The script outputs results sorted by lowest average time and saves them to both **TXT** and **JSON** files for easy reference.  
It also supports **timeout control** per query and logs servers that exceed the configured threshold.

---

## Features
- Reads DNS server list from an **external JSON** file.
- Reads domain list from an **external JSON** file.
- Displays **progress bar** per server and per query (no flicker).
- Skips slow servers exceeding a configurable **timeout**.
- Results sorted by **lowest Avg_ms**.
- Appends results to `_dns-bench-result.txt` with timestamp.
- Saves **TOP 5** fastest servers to `_dns-t5.json`.
- Logs all exceeded servers/domains in `_dns-bench-result.txt`.
- Supports **multiple server/domain lists** (just switch the JSON files).
- Compatible with **Windows PowerShell 5.1+** and **PowerShell 7+**.

---

## Requirements
- **Windows PowerShell 5.1** or later (**PowerShell 7+** recommended).
- Internet access to resolve domains.
- Permission to run scripts:
  ```powershell
  Set-ExecutionPolicy Bypass -Scope Process
  ```

---

## Installation
Clone the repository:
```powershell
git clone https://github.com/blankbash/dns-bench.git
cd dns-bench
```

---

## Usage

### 1. Create a JSON server list
Example `servers.json`:
```json
[
  { "Name": "Quad9 1", "IP": "9.9.9.9" },
  { "Name": "Cloudflare 1", "IP": "1.1.1.1" }
]
```

### 2. Create a JSON domain list
Example `domains.json`:
```json
[
  "microsoft.com",
  "apple.com",
  "cloudflare.com",
  "google.com",
  "amazon.com",
  "netflix.com",
  "spotify.com",
  "wikipedia.org"
]
```

### 3. Run the benchmark
```powershell
.\dns-bench.ps1 -ServersFile servers.json -DomainsFile domains.json -Runs 10 -TimeoutMs 800 -MaxTimeouts 1
```

**Parameters**:
- `-ServersFile` / `-f` → Path to the JSON file with DNS servers (default: `servers.json`).
- `-DomainsFile` / `-n` → Path to the JSON file with domains to test (default: `domains.json`).
- `-Runs` / `-r` → Number of repetitions per domain/server (default: `10`).
- `-TimeoutMs` / `-t` → Timeout in milliseconds per query (default: `800`).
- `-MaxTimeouts` / `-x` → Maximum allowed timeouts per server before skipping it (default: `1`).

---

## Output
**Console**: Table sorted by `Avg_ms` (lowest first).  
**Files generated**:
- `_dns-bench-result.txt` → Full benchmark history with timestamp, including exceeded list if applicable.
- `_dns-t5.json` → TOP 5 fastest servers (Name/IP schema).

Example output in console:
```
Name           Server      Samples Avg_ms Median_ms P95_ms Min_ms Max_ms
----           ------      ------- ------ --------- ------ ------ ------
Cloudflare 1   1.1.1.1     80      12.45  11.90     20.05  10.23  25.67
Google 1       8.8.8.8     80      15.22  14.88     23.14  12.75  29.34

Exceeded list:
Name           Server      Domain          Run ThresholdMs Reason
----           ------      ------          --- ----------- ------
Quad9 1        9.9.9.9     amazon.com      1   800         Exceeded response limit
```

---

## Author
Blankbash
