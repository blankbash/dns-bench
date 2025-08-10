<#
===============================================================================
 dns-bench.PS1
 Version: 1.3
 License: GNU GPL v3
-------------------------------------------------------------------------------
Description:
  DNS server benchmark script using PowerShell.
  Measures average time, median, P95, minimum, and maximum response times
  for a list of domains, repeating queries for each configured server.

Features:
  - Reads server list from an external JSON file.
  - Progress bar per server and per query.
  - Output sorted by lowest average time (Avg_ms).
  - Exports results to file "_dns-bench-result.txt" with date/time.
  - Exports TOP 5 servers to "_dns-t5.json".
  - Supports multiple lists (just change the JSON file).

Requirements:
  - Windows PowerShell 5.1 or later (or PowerShell 7+).
  - Internet access to resolve domains.
  - Script execution permissions (Set-ExecutionPolicy).

Usage:
  1. Create a JSON file with the list of DNS servers:
     [
       { "Name": "Quad9 1", "IP": "9.9.9.9" },
       { "Name": "Cloudflare 1", "IP": "1.1.1.1" }
     ]

  2. Create a JSON file with the list of domains:
     [
       "microsoft.com",
       "google.com",
       "cloudflare.com"
     ]

  3. Run:
     powershell.exe -ExecutionPolicy Bypass -File .\dns-bench.ps1 -ServersFile servers.json -DomainsFile domains.json -Runs 10

Parameters:
  -ServersFile   Path to the JSON file containing the DNS servers.
    -Alias -f
  -DomainsFile   Path to the JSON file containing the domains to test.
    -Alias -n
  -Runs          Number of repetitions per domain/server (default: 10).
    -Alias -r

Output:
  - Console: table sorted by Avg_ms (lowest first).
  - File: _dns-bench-result.txt in the current directory, full table.
  - File: _dns-t5.json in the current directory, Name/IP schema.

Author:
  Erik Lopes de Oliveira (Blankbash)
===============================================================================
#>

param(
  [Alias("f")]
  [string]$ServersFile = "servers.json",
  [Alias("r")]
  [int]$Runs = 10,
  [Alias("n")]
  [string]$DomainsFile = "domains.json"
)

$host.privatedata.ProgressForegroundColor = "Black"
$host.privatedata.ProgressBackgroundColor = "DarkMagenta"

# 0) Clear local DNS cache
ipconfig /flushdns | Out-Null

# 1) Utilities
function Import-Servers {
  param([string]$Path)
  if (-not (Test-Path -Path $Path)) { throw "Server list file not found: ${Path}" }
  try { $data = Get-Content -Raw -Path $Path | ConvertFrom-Json }
  catch { throw "Failed to read/parse JSON in ${Path}: $($_.Exception.Message)" }
  if (-not $data -or $data.Count -eq 0) { throw "No servers found in ${Path}" }
  foreach ($s in $data) {
    if (-not $s.IP -or -not $s.Name) {
      throw "Invalid entry (requires {Name, IP}). Example: {`"Name`":`"Cloudflare 1`",`"IP`":`"1.1.1.1`"}"
    }
  }
  return $data
}

function Import-Domains {
  param([string]$Path)
  if (-not (Test-Path -Path $Path)) { throw "Domain list file not found: ${Path}" }
  try { $data = Get-Content -Raw -Path $Path | ConvertFrom-Json }
  catch { throw "Failed to read/parse JSON in ${Path}: $($_.Exception.Message)" }
  if (-not $data -or $data.Count -eq 0) { throw "No domains found in ${Path}" }
  # validate all entries are non-empty strings
  foreach ($d in $data) {
    if (-not ($d -is [string]) -or [string]::IsNullOrWhiteSpace($d)) {
      throw "Invalid domain entry. Expect array of strings. Example: [`"microsoft.com`", `"google.com`"]"
    }
  }
  return $data
}

function Test-DNSRTT {
  param(
    [string]$Name,
    [string]$Server,
    [string[]]$Names,
    [int]$Runs,
    [int]$ServerIndex = 1,
    [int]$ServerTotal = 1
  )
  $results = @()
  $parentId = 1000 + $ServerIndex

  for ($i=1; $i -le $Runs; $i++) {
    $pctOuter = [int](($i-1)/$Runs*100)
    Write-Progress -Id $parentId -Activity "DNS Benchmark" `
      -Status ("Server {0}/{1}: {2} ({3})  run {4}/{5}" -f $ServerIndex, $ServerTotal, $Name, $Server, $i, $Runs) `
      -PercentComplete $pctOuter

    $j = 0
    foreach ($n in $Names) {
      $j++
      $pctInner = [int](($j-1)/$Names.Count*100)
      Write-Progress -Id ($parentId+1) -ParentId $parentId -Activity "Queries" `
        -Status ("{0} ({1}) @ {2}  {3}/{4}" -f $Name, $Server, $n, $j, $Names.Count) `
        -PercentComplete $pctInner

      $t = [System.Diagnostics.Stopwatch]::StartNew()
      try { Resolve-DnsName -Server $Server -Type A -NoHostsFile -DnsOnly -Name $n -ErrorAction Stop | Out-Null } catch { } finally {
        $t.Stop(); $results += $t.Elapsed.TotalMilliseconds
      }
    }
    Start-Sleep -Milliseconds 50
  }

  Write-Progress -Id ($parentId+1) -Completed -Activity "Queries"
  Write-Progress -Id $parentId -Completed -Activity "DNS Benchmark"

  [PSCustomObject]@{
    Name      = $Name
    Server    = $Server
    Samples   = ${results}.Count
    Avg_ms    = [Math]::Round((${results} | Measure-Object -Average).Average,2)
    Median_ms = [Math]::Round((${results} | Sort-Object | Select-Object -Index ([int](${results}.Count/2))),2)
    P95_ms    = [Math]::Round((${results} | Sort-Object | Select-Object -Last ([int]([math]::Ceiling(${results}.Count*0.05))) | Measure-Object -Maximum).Maximum,2)
    Min_ms    = [Math]::Round((${results} | Measure-Object -Minimum).Minimum,2)
    Max_ms    = [Math]::Round((${results} | Measure-Object -Maximum).Maximum,2)
  }
}

# 3) Load servers and domains
$servers = Import-Servers -Path $ServersFile
$names   = Import-Domains -Path $DomainsFile

# 4) Run benchmark (sequential, with progress)
$summary = @()
for ($idx=0; $idx -lt $servers.Count; $idx++) {
  $s = $servers[$idx]
  $summary += Test-DNSRTT -Name $s.Name -Server $s.IP -Names $names -Runs $Runs -ServerIndex ($idx+1) -ServerTotal $servers.Count
}

$sorted = $summary | Sort-Object Avg_ms

# 5) Output TXT (append history)
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$outPathTxt = Join-Path (Get-Location) "_dns-bench-result.txt"
if (-not (Test-Path -Path $outPathTxt)) { New-Item -ItemType File -Path $outPathTxt -Force | Out-Null }
$headerLine = "---- DNS Bench Result - ${timestamp} (Servers: ${ServersFile} | Domains: ${DomainsFile}) ----"
$table = $sorted | Format-Table Name,Server,Samples,Avg_ms,Median_ms,P95_ms,Min_ms,Max_ms -Auto | Out-String
Add-Content -Path $outPathTxt -Encoding UTF8 -Value $headerLine
Add-Content -Path $outPathTxt -Encoding UTF8 -Value $table
Add-Content -Path $outPathTxt -Encoding UTF8 -Value ""

# 6) Output TOP 5 as JSON {Name, IP}
$top5 = $sorted | Select-Object -First 5 `
  @{ Name = 'Name'; Expression = { $_.Name } }, `
  @{ Name = 'IP';   Expression = { $_.Server } }
$outPathJson = Join-Path (Get-Location) "_dns-t5.json"
$top5 | ConvertTo-Json -Depth 3 | Set-Content -Path $outPathJson -Encoding UTF8

# Console
$sorted | Format-Table Name,Server,Samples,Avg_ms,Median_ms,P95_ms,Min_ms,Max_ms -Auto
Write-Host "`nResults appended to: $outPathTxt"
Write-Host "TOP 5 (schema {Name, IP}) saved to: $outPathJson"