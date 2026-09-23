<#
  发布前检查（推送前跑一次）
  用法：双击「发布前检查.cmd」，或在 PowerShell 里运行本脚本。

  两档设计，避免"告警疲劳"（详见《博客建设方案.md》第 7 章）：
    [高危] 必须处理 —— 非文档文件里的真实密钥特征、敏感文件、坏图、绝对路径图片
    [提示] 人工确认 —— 具体内网地址、疑似凭据、订阅链接、超过 500KB 的大图
                            以及 .md 文档里出现的"密钥格式示例"（文档里往往是教学示例）

  设计取舍：
    - .md 属于文档，里面出现 `sk-`、`AKIA` 这类"格式说明"很正常 → 只提示，不当高危；
    - 真正的配置/脚本文件里出现同样的特征 → 直接高危；
    - 本脚本自身会被跳过（它的规则里就写着这些特征字符串）。
#>

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

$high = New-Object System.Collections.ArrayList
$warn = New-Object System.Collections.ArrayList
function Add-High($m) { [void]$high.Add($m) }
function Add-Warn($m) { [void]$warn.Add($m) }

$selfNames = @('发布前检查.ps1', '发布前检查.cmd')
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
# 真实密钥的格式特征（收紧过的，避免把文档里的"sk-"这类字样当成密钥）
$secretPatterns = @(
  'sk-[A-Za-z0-9]{20,}',
  'ghp_[A-Za-z0-9]{20,}',
  'github_pat_[A-Za-z0-9_]{20,}',
  'xoxb-[0-9]{8,}-[0-9A-Za-z-]{10,}',
  'xoxp-[0-9]{8,}-[0-9A-Za-z-]{10,}',
  'AKIA[0-9A-Z]{16}',
  '-----BEGIN [A-Z ]*PRIVATE KEY',
  '(?i)authorization:\s*bearer\s+\S{20,}'
)
# 出现这些字样就视为占位/示例，不再告警
$placeholders = @('192.168.x.x', '10.0.0.x', '${', 'changeme', 'YOUR_', 'xxxxx', 'example.com', '占位', 'XXX', '示例', '例如', '教学')
# 凭据赋值：值属于这些"无害词"就跳过
$safeValues = @('write', 'read', 'none', 'true', 'false', 'changeme', 'your_token', 'your_key')
$scanExt = @('.md', '.toml', '.yaml', '.yml', '.json', '.txt', '.ps1', '.cmd', '.js', '.xml', '.conf', '.ini')

$files = Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $scanExt -contains $_.Extension.ToLower() -and -not (Is-Skipped $_.FullName) -and $selfNames -notcontains $_.Name }

foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1)
  $isDoc = ($f.Extension.ToLower() -eq '.md')
  $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    $no = $i + 1
    $isPlaceholder = $false
    foreach ($p in $placeholders) { if ($line.IndexOf($p, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $isPlaceholder = $true; break } }

    foreach ($sp in $secretPatterns) {
      if ($line -match $sp) {
        if ($isDoc) { Add-Warn "[文档] $rel`:$no 出现密钥格式字样（多半是示例，扫一眼确认） -> $($line.Trim())" }
        else { Add-High "$rel`:$no 疑似真实密钥 -> $($line.Trim())" }
      }
    }
    if ($isPlaceholder) { continue }

    if ($line -match '192\.168\.\d{1,3}\.\d{1,3}') { Add-Warn "$rel`:$no 出现具体内网地址 -> $($line.Trim())" }
    if ($line -match '(?<![\d.])10\.\d{1,3}\.\d{1,3}\.\d{1,3}(?![\d.])') { Add-Warn "$rel`:$no 出现具体内网地址 -> $($line.Trim())" }
    if ($line -match '(?i)(password|passwd|api_?key|secret|token)\s*[:=]\s*["'']?([A-Za-z0-9_\-\.\+/]{8,})') {
      $val = $Matches[2]
      if ($safeValues -notcontains $val.ToLower()) { Add-Warn "$rel`:$no 疑似真实凭据 -> $($line.Trim())" }
    }
    if ($line -match '(?i)https?://[^\s"'']*[?&](token|sub|subscribe|key)=') { Add-Warn "$rel`:$no 疑似含密钥的订阅/带参链接 -> $($line.Trim())" }
  }
}

# ---------- 3. 坏图检测（引用的图片必须真实存在） ----------
$contentDir = Join-Path $root 'content'
if (Test-Path $contentDir) {
  $imgRegex = [regex]'!\[[^\]]*\]\((?<p>[^)\s]+)'
  $mdFiles = Get-ChildItem -Path $contentDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue
  foreach ($m in $mdFiles) {
    $rel = $m.FullName.Substring($root.Length + 1)
    $text = Get-Content -LiteralPath $m.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    # 先剥掉「代码块」与「行内代码」再检查：
    # 否则文章里教读者"不要这样写图片"的示例（如 ![[...]]）会被误报成真的坏图
    $scanText = [regex]::Replace($text, '(?s)```.*?```', ' ')
    $scanText = [regex]::Replace($scanText, '`[^`]*`', ' ')
    if ($scanText -match '!\[\[') { Add-Warn "$rel 出现 wiki 链接写法 ![[...]]，Hugo 不认 —— 请改成 ![](图片.webp)" }
    foreach ($match in $imgRegex.Matches($scanText)) {
      $p = $match.Groups['p'].Value.Trim()
      if ($p -match '^(https?:)?//' -or $p -match '^\{\{') { continue }
      if ($p -match '^[A-Za-z]:\\' -or $p -match '^file:') { Add-High "$rel 图片用了绝对路径 -> $p（请改成与 md 同目录的相对路径）"; continue }
      $clean = $p.Split('#')[0].Split('?')[0]
      $target = Join-Path $m.DirectoryName $clean
      if (-not (Test-Path $target)) { Add-High "$rel 引用的图片找不到 -> $p" }
    }
  }

  # ---------- 4. 大图提醒 ----------
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
