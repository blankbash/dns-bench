# DNS Bench (PowerShell)

## Overview
`dns-bench.ps1` is a PowerShell script for benchmarking DNS servers.  
It measures **average time**, **median**, **P95**, **minimum**, and **maximum** response times for a given list of domains, repeating the queries for each configured server.  

The script outputs results sorted by lowest average time and saves them to both **TXT** and **JSON** files for easy reference.

---

## Features
- Reads DNS server list from an **external JSON** file.
- Displays **progress bar** per server and per query.
- Results sorted by **lowest Avg_ms**.
- Appends results to `_dns-bench-result.txt` with timestamp.
- Saves **TOP 5** fastest servers to `_dns-t5.json`.
- Supports **multiple server lists** (just switch the JSON file).
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

### 2. Run the benchmark
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\dns-bench.ps1 -ServersFile servers.json -Runs 10
```

**Parameters**:
- `-ServersFile` / `-f`: Path to the JSON file with DNS servers (default: `servers.json`).
- `-Runs` / `-r`: Number of repetitions per domain/server (default: `10`).

---

## Output
**Console**: Table sorted by `Avg_ms` (lowest first).  
**Files generated**:
- `_dns-bench-result.txt` → Full benchmark history with timestamp.
- `_dns-t5.json` → TOP 5 fastest servers (Name/IP schema).

Example output in console:
```
Name           Server      Samples Avg_ms Median_ms P95_ms Min_ms Max_ms
----           ------      ------- ------ --------- ------ ------ ------
Cloudflare 1   1.1.1.1     80      12.45  11.90     20.05  10.23  25.67
Google 1       8.8.8.8     80      15.22  14.88     23.14  12.75  29.34
```

---

## Author
Blankbash 
License: **GNU GPL v3**
