<#
  发布前检查（推送前跑一次）
  用法：双击「发布前检查.cmd」，或在 PowerShell 里运行本脚本。

  分成两档，避免"告警疲劳"：
    [高危] 必须处理 —— 真实密钥特征、敏感文件、坏图、绝对路径图片
    [提示] 人工确认 —— 具体内网地址、疑似真实凭据、超过 500KB 的大图

  设计说明见《博客建设方案.md》第 7 章。
#>

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

$high = New-Object System.Collections.ArrayList
$warn = New-Object System.Collections.ArrayList
function Add-High($m) { [void]$high.Add($m) }
function Add-Warn($m) { [void]$warn.Add($m) }

$skipDirs = @("$root\.git\", "$root\.research\", "$root\themes\", "$root\public\", "$root\resources\", "$root\.installer\", "$root\node_modules\")
function Is-Skipped($full) {
  foreach ($d in $skipDirs) { if ($full.StartsWith($d, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
  return $false
}

# ---------- 1. 不该存在的文件 / 目录 ----------
foreach ($d in @('private', 'secrets')) {
  if (Test-Path (Join-Path $root $d)) { Add-High "存在不该提交的目录：$d/" }
}
foreach ($pat in @('.env', '.env.*', '*.pem', '*.key', '*.p12', '*.pfx', 'id_rsa', 'id_ed25519')) {
  Get-ChildItem -Path $root -Recurse -File -Force -Filter $pat -ErrorAction SilentlyContinue |
    Where-Object { -not (Is-Skipped $_.FullName) } |
    ForEach-Object { Add-High "发现敏感文件：$($_.FullName.Substring($root.Length + 1))" }
}

# ---------- 2. 内容里的密钥特征 ----------
$secretPatterns = @('sk-[A-Za-z0-9]{16,}', 'ghp_[A-Za-z0-9]{20,}', 'github_pat_', 'xoxb-', 'AKIA[0-9A-Z]{12,}', 'BEGIN [A-Z ]*PRIVATE KEY')
$placeholders = @('192.168.x.x', '10.0.0.x', '${', 'changeme', 'YOUR_', 'xxxxx', 'example.com', '占位', 'XXX')
$scanExt = @('.md', '.toml', '.yaml', '.yml', '.json', '.txt', '.ps1', '.cmd', '.js', '.xml')

$files = Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $scanExt -contains $_.Extension.ToLower() -and -not (Is-Skipped $_.FullName) }

foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1)
  $lines = @(Get-Content $f.FullName -ErrorAction SilentlyContinue)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $no = $i + 1
    foreach ($sp in $secretPatterns) {
      if ($line -match $sp) { Add-High "$rel`:$no 疑似真实密钥 -> $($line.Trim())" }
    }
    $isPlaceholder = $false
    foreach ($p in $placeholders) { if ($line.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $isPlaceholder = $true; break } }
    if (-not $isPlaceholder) {
      if ($line -match '192\.168\.\d{1,3}\.\d{1,3}') { Add-Warn "$rel`:$no 出现具体内网地址 -> $($line.Trim())" }
      if ($line -match '(?<![\d.])10\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![\d.])') { Add-Warn "$rel`:$no 出现具体内网地址 -> $($line.Trim())" }
      if ($line -match '(?i)(password|passwd|token|api_?key|secret)\s*[:=]\s*\S') { Add-Warn "$rel`:$no 疑似真实凭据 -> $($line.Trim())" }
    }
  }
}

# ---------- 3. 坏图检测（图片引用指向的文件必须存在） ----------
$contentDir = Join-Path $root 'content'
if (Test-Path $contentDir) {
  $imgRegex = [regex]'!\[[^\]]*\]\((?<p>[^)\s]+)'
  $mdFiles = Get-ChildItem -Path $contentDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue
  foreach ($m in $mdFiles) {
    $rel = $m.FullName.Substring($root.Length + 1)
    $text = Get-Content $m.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    if ($text -match '!\[\[') { Add-Warn "$rel 出现 wiki 链接写法 ![[...]]，Hugo 不认 —— 请改成 ![](图片.webp)" }
    foreach ($match in $imgRegex.Matches($text)) {
      $p = $match.Groups['p'].Value.Trim()
      if ($p -match '^(https?:)?//' -or $p -match '^\{\{') { continue }
      if ($p -match '^[A-Za-z]:\\' -or $p -match '^file:') { Add-High "$rel 图片用了绝对路径 -> $p（请改成与 md 同目录的相对路径）"; continue }
      $clean = $p.Split('#')[0].Split('?')[0]
      $target = Join-Path $m.DirectoryName $clean
      if (-not (Test-Path $target)) { Add-High "$rel 引用的图片找不到 -> $p" }
    }
  }
}

# ---------- 4. 大图提醒 ----------
if (Test-Path $contentDir) {
  Get-ChildItem -Path $contentDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif') -contains $_.Extension.ToLower() -and $_.Length -gt 500KB } |
    ForEach-Object { Add-Warn "图片超过 500KB：$($_.FullName.Substring($root.Length + 1))（$([math]::Round($_.Length / 1KB)) KB）建议压缩后再提交" }
}

# ---------- 输出 ----------
Write-Host ''
Write-Host '========== 发布前检查 ==========' -ForegroundColor Cyan
if ($warn.Count -gt 0) {
  Write-Host ''
  Write-Host "[提示] 人工确认一下（$($warn.Count) 条）：" -ForegroundColor Yellow
  $warn | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
}
if ($high.Count -gt 0) {
  Write-Host ''
  Write-Host "[高危] 必须处理（$($high.Count) 条）：" -ForegroundColor Red
  $high | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
}
Write-Host ''
if ($high.Count -gt 0) {
  Write-Host '❌ 存在高危项：先修掉再推送！' -ForegroundColor Red
  exit 1
}
elseif ($warn.Count -gt 0) {
  Write-Host '✅ 高危项为空（提示项请自己判断一下）。' -ForegroundColor Green
  exit 0
}
else {
  Write-Host '✅ 没发现问题，可以发布。' -ForegroundColor Green
  exit 0
}
