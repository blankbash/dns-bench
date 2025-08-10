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
   powershell.exe -ExecutionPolicy Bypass -File .\dns-bench.ps1 ^
     -ServersFile servers.json ^
     -DomainsFile domains.json ^
     -Runs 10 ^
     -TimeoutMs 800 ^
     -MaxTimeouts 1

Parameters:
    -ServersFile Path to the JSON file containing the DNS servers.
        Alias: -f

    -DomainsFile Path to the JSON file containing the domains to test.
        Alias: -n

    -Runs Number of repetitions per domain/server (default: 10).
        Alias: -r

    -TimeoutMs Per-query timeout in milliseconds (default: 800). If a single DNS query takes longer, it is treated as timed out.
        Alias: -t

    -MaxTimeouts Number of consecutive timeouts tolerated per server before aborting that server (default: 1).
        Alias: -x

Output:
    Console: table sorted by Avg_ms (lowest first).
    File: _dns-bench-result.txt (appended; includes “Exceeded” table when applicable).
    File: _dns-t5.json (TOP 5 fastest; schema { Name, IP }).

Author:
  Erik Lopes de Oliveira (Blankbash)
===============================================================================
#>

param(
  [Alias("f")]
  [string]$ServersFile = "servers.json",
  [Alias("n")]
  [string]$DomainsFile = "domains.json",
  [Alias("r")]
  [int]$Runs = 10,
  [Alias("t")]
  [int]$TimeoutMs = 800,
  [Alias("x")]
  [int]$MaxTimeouts = 1
)

$host.privatedata.ProgressForegroundColor = "Black"
$host.privatedata.ProgressBackgroundColor = "DarkMagenta"

ipconfig /flushdns | Out-Null

# -------------------- Carregadores --------------------
function Import-Servers {
  param([string]$Path)
  if (-not (Test-Path -Path $Path)) { throw "Server list file not found: ${Path}" }
  try { $data = Get-Content -Raw -Path $Path | ConvertFrom-Json } catch {
    throw "Failed to read/parse JSON in ${Path}: $($_.Exception.Message)"
  }
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
  if (-not (Test-Path -Path $Path)) { throw "Domains file not found: ${Path}" }
  try { $data = Get-Content -Raw -Path $Path | ConvertFrom-Json } catch {
    throw "Failed to read/parse JSON in ${Path}: $($_.Exception.Message)"
  }
  if (-not $data) { throw "No domains found in ${Path}" }

  # Suporta: ["google.com","apple.com"] OU [{Domain:"..."}, {Name:"..."}]
  $list = @()
  foreach ($d in $data) {
    if ($d -is [string] -and $d.Trim()) { $list += $d.Trim(); continue }
    if ($d.PSObject.Properties.Name -contains 'Domain' -and $d.Domain) { $list += ($d.Domain.Trim()); continue }
    if ($d.PSObject.Properties.Name -contains 'Name'   -and $d.Name)   { $list += ($d.Name.Trim()); continue }
  }
  $list = $list | Where-Object { $_ } | Select-Object -Unique
  if ($list.Count -eq 0) { throw "Domains file ${Path} has no usable entries." }
  return $list
}
# ------------------------------------------------------

# -------------------- Resolver com timeout --------------------
function Resolve-QueryWithTimeout {
  param(
    [string]$Server,
    [string]$Domain,
    [int]$TimeoutMs
  )
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $job = Start-Job -ScriptBlock {
    param($srv,$dom)
    Resolve-DnsName -Server $srv -Type A -NoHostsFile -DnsOnly -Name $dom -ErrorAction Stop | Out-Null
  } -ArgumentList $Server,$Domain

  $ok = Wait-Job -Id $job.Id -Timeout ([math]::Ceiling($TimeoutMs/1000))
  if (-not $ok) {
    Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
    Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
    return $null
  }

  $failed = $false
  try { Receive-Job -Id $job.Id -ErrorAction Stop | Out-Null } catch { $failed = $true }
  Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
  $sw.Stop()

  if ($failed) { return $null }
  return $sw.Elapsed.TotalMilliseconds
}
# -------------------------------------------------------------

# Lista global de excedidos
$script:ExceededList = @()

function Test-DNSRTT {
  param(
    [string]$Name,
    [string]$Server,
    [string[]]$Names,
    [int]$Runs,
    [int]$ServerIndex = 1,
    [int]$ServerTotal = 1,
    [int]$TimeoutMs = 800,
    [int]$MaxTimeouts = 1
  )
  $results = @()
  $parentId = 1000 + $ServerIndex
  $timeouts = 0
  $aborted = $false

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

      $ms = Resolve-QueryWithTimeout -Server $Server -Domain $n -TimeoutMs $TimeoutMs
      if ($null -eq $ms) {
        $timeouts++
        if ($timeouts -ge $MaxTimeouts) {
          $script:ExceededList += [PSCustomObject]@{
            Name        = $Name
            Server      = $Server
            Domain      = $n
            Run         = $i
            ThresholdMs = $TimeoutMs
            Reason      = "Exceeded response limit"
          }
          $aborted = $true
          break
        }
        continue
      }
      $results += $ms
    }
    if ($aborted) { break }
    Start-Sleep -Milliseconds 50
  }

  Write-Progress -Id ($parentId+1) -Completed -Activity "Queries"
  Write-Progress -Id $parentId -Completed -Activity "DNS Benchmark"

  if ($aborted -and $results.Count -eq 0) { return $null }

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

# -------------------- Carregar arquivos --------------------
$servers = Import-Servers -Path $ServersFile
$names   = Import-Domains -Path $DomainsFile
# -----------------------------------------------------------

# -------------------- Rodar benchmark ----------------------
$summary = @()
for ($idx=0; $idx -lt $servers.Count; $idx++) {
  $s = $servers[$idx]
  $res = Test-DNSRTT -Name $s.Name -Server $s.IP -Names $names -Runs $Runs `
    -ServerIndex ($idx+1) -ServerTotal $servers.Count `
    -TimeoutMs $TimeoutMs -MaxTimeouts $MaxTimeouts
  if ($null -ne $res) { $summary += $res }
}
$sorted = $summary | Sort-Object Avg_ms
# -----------------------------------------------------------

# -------------------- Saídas -------------------------------
$timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$outPathTxt = Join-Path (Get-Location) "_dns-bench-result.txt"
if (-not (Test-Path -Path $outPathTxt)) { New-Item -ItemType File -Path $outPathTxt -Force | Out-Null }

$headerLine = "---- DNS Bench Result - ${timestamp} (Servers: ${ServersFile}, Domains: ${DomainsFile}, Timeout=${TimeoutMs}ms, MaxTimeouts=${MaxTimeouts}) ----"
$table = $sorted | Format-Table Name,Server,Samples,Avg_ms,Median_ms,P95_ms,Min_ms,Max_ms -Auto | Out-String

Add-Content -Path $outPathTxt -Encoding UTF8 -Value $headerLine
Add-Content -Path $outPathTxt -Encoding UTF8 -Value $table

if ($script:ExceededList.Count -gt 0) {
  $exTable = $script:ExceededList | Format-Table Name,Server,Domain,Run,ThresholdMs,Reason -Auto | Out-String
  Add-Content -Path $outPathTxt -Encoding UTF8 -Value "Exceeded (timeout or error):"
  Add-Content -Path $outPathTxt -Encoding UTF8 -Value $exTable
}
Add-Content -Path $outPathTxt -Encoding UTF8 -Value ""

# TOP5 JSON {Name, IP}
$top5 = $sorted | Select-Object -First 5 `
  @{ Name = 'Name'; Expression = { $_.Name } }, `
  @{ Name = 'IP';   Expression = { $_.Server } }
$outPathJson = Join-Path (Get-Location) "_dns-t5.json"
$top5 | ConvertTo-Json -Depth 3 | Set-Content -Path $outPathJson -Encoding UTF8

# Console
$sorted | Format-Table Name,Server,Samples,Avg_ms,Median_ms,P95_ms,Min_ms,Max_ms -Auto
if ($script:ExceededList.Count -gt 0) {
  "`nExceeded list:" | Write-Host
  $script:ExceededList | Format-Table Name,Server,Domain,Run,ThresholdMs,Reason -Auto
}
Write-Host "`nResults appended to: $outPathTxt"
Write-Host "TOP 5 (schema {Name, IP}) saved to: $outPathJson"
# -----------------------------------------------------------