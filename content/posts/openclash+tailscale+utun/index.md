---
title: Tailscale 在 OpenClash 代理环境下自动打洞成功方案
date: 2026-09-24T11:25:17+08:00
lastmod: 2026-09-24
draft: false
description: 定时从 Tailscale 官方公开接口拉取 DERP 服务器 IP 列表，自动生成直连规则并写入 OpenClash 自定义规则文件，使Tailscale打洞探测流量正常。
categories:
  - 折腾记录
tags:
  - 软路由
  - OpenWrt
  - ImmortalWrt
  - OpenClash
  - Tailscale
showHero: true
heroStyle: big
showTableOfContents: true
showTaxonomies: true
---

## Tailscale 在 OpenClash 代理环境下自动打洞成功方案

## 一、概述

在软路由上同时运行 OpenClash 和 Tailscale，会遇到一个问题：**Tailscale 无法与官方DERP直连，导致打洞失败，进而远端设备无法与软路由直连**，软路由上执行tailscale netcheck检查：IPV4 (no addr found)、UDP false。

根因不在 Tailscale 本身，而在于 OpenClash 的透明代理接管了路由器**自身**的出站流量，把 Tailscale 用于 NAT 打洞的探测包一并送进了代理通道，导致它拿不到正确的公网端点。

本文的方案是：定时从 Tailscale 官方公开接口拉取 DERP 服务器 IP 列表，自动生成直连规则并写入 OpenClash 自定义规则文件，使Tailscale打洞探测流量正常。部署完成后全自动运行，无需人工干预。

---

## 二、适用环境与故障现状

### 2.1 适用环境

本方案适用于**软路由（OpenWrt / ImmortalWrt）**上同时部署 **OpenClash** 与 **Tailscale**，且**OpenClash 代理本机流量、软路由自身也需走代理**的情况（例如它被Tailscale远端设备当作 Exit Node 使用）。

我的实际环境是：

```
软路由固件版本：ImmortalWrt 25.12.1 r37978

Openclash插件版本：v0.47.156，内核版本：alpha-ge183c58，开启“路由本机代理”

Tailscale版本：1.98.3-1 (OpenWrt)，开启“通告出口节点”
```

我期望达成的效果：Tailscale能自动打洞成功，但不能影响软路由自身、局域网设备、Tailscale exit node出口流量的正常代理。

### 2.2 故障状态

**Tailscale 打洞失败，连接状态** —— 远端节点在线但走中继：

```
100.xxx.xxx.100  pc-20260625  xxxxx@  windows  active; relay "sin"
```

关键判据是 `relay "sin"`，正常应为 `direct x.x.x.x:port`。

**自检结果** —— `tailscale netcheck` 反映 Tailscale 能否探测到自身公网端点：

```
Report:
        * UDP: false
        * IPv4: (no addr found)
```

`IPv4: (no addr found)` 说明完全没拿到公网 IP:端口映射，NAT 类型判定失败。

**OpenClash 日志** —— 这是破案的关键：

```
[信息] [UDP] 192.168.16.253:40856 --> 172.237.61.190:3478  match 使用 机场节点
[信息] [TCP] 192.168.16.253:33274 --> 45.159.98.196:80    match 使用 机场节点
[信息] [TCP] 192.168.16.253:37364 --> 162.248.221.215:80  match 使用 机场节点
```

源地址 `192.168.16.253` 是**软路由本机**，目的端口 `3478`（STUN）与 `80`（DERP 探测）正是 Tailscale 的探测流量。日志中的目的 IP 逐一比对官方 DERP 列表后**全部命中**：`172.237.61.190`（sao/derp11g，兼作 STUN）、`162.248.221.199/215/248`（tor/21b~21d）、`45.159.98.196/145`（waw/22b、22d）。

快速确证方法：停掉 OpenClash 后重跑 `tailscale netcheck`，若 `IPv4` 立刻正常即可确认。

```bash
/etc/init.d/openclash stop && sleep 5 && tailscale netcheck
```

---

## 三、根因：打洞成功需要达成的条件

Tailscale 打洞成功需满足两个条件：

| 条件        | 依赖流量                         | 被代理后的后果                    |
| --------- | ---------------------------- | -------------------------- |
| 探测到自身公网端点 | 向 STUN 发 UDP 包（默认 `3478`）    | 拿到的是代理节点出口地址，源端口被重写，映射信息错误 |
| 维持信令通道    | 与控制面/DERP 通信（TCP `443`/`80`） | 通道虽通，但协商出的端点不可用            |

**第一个环节被破坏后后续全部失效** —— 这就是网络正常、账号也正常，却永远只能走中继的原因。

---

## 四、需求边界

1. Tailscale打洞的STUN / DERP 探测流量必须**直连**，不经过代理通道
2. **软路由自身、局域网设备和Tailscale Exit Node出口流量的代理不受影响**，仍然经过 OpenClash 代理
3. DERP 服务器 IP 会变动，必须**自动跟进**，不靠人工维护
4. 长期稳定运行，更新过程不造成明显断网

---

## 五、方案选型

| 方案                   | 做法                                           | 结论                                                                                                                                                                                                                 |
| -------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 关闭路由器本机代理            | 设置里关闭本机代理，或把本机 IP 加入绕过列表                     | ❌ 软路由自身失去代理能力，Exit Node 场景失效，违背需求边界 2                                                                                                                                                                              |
| 进程级规则                | 添加 `PROCESS-NAME,tailscaled,DIRECT`          | ❌ 实测无效。依赖 meta 内核且需开启进程名探测，本机 TPROXY 场景下稳定匹配不到 tailscaled 进程                                                                                                                                                       |
| 100.64.0.0/10 加进绕过列表 | 添加 IP-CIDR,100.64.0.0/10,DIRECT,no-resolve   | ❌ 实测无效。一、规则匹配看的是数据包的**目的地址**，而上述探测包的目的地址是 DERP 服务器的**公网 IP**，源地址是本机内网 IP，不会出现 `100.64.0.0/10`，规则不会被命中。二、该网段解决的是"访问 Tailscale 网段时不要走代理"，属业务流量分流；而我们面对的是"路由器自身的探测流量不要走代理"，属控制面问题。只有打洞成功之后才会产生以该网段为目的地址的流量，现在恰恰卡在这之前。 |
| **自定义规则 + 定时更新**     | 定时拉取官方 DERP IP 列表，生成 `IP-CIDR` 直连规则写入自定义规则文件 | ✅ 仅针对 DERP 地址直连，不影响其余流量，全自动跟进变动                                                                                                                                                                                    |

---

## 六、核心思路

Tailscale 官方提供公开的 DERP 清单接口，返回全部区域与节点信息：

```
主用：https://controlplane.tailscale.com/derpmap/default
备用：https://login.tailscale.com/derpmap/default于是方案变得直接：**定时拉取 → 提取全部节点 IPv4 → 去重排序 → 生成 `IP-CIDR,x.x.x.x/32,DIRECT` 规则 → 写入 OpenClash 自定义规则文件 → 重启生效**。
```

通过脚本定时拉取官方 DERP IP 列表，生成 `IP-CIDR` 直连规则写入自定义规则文件，OpenClash 启动时会将其**前置到整个规则链最前面**，优先于后续各类策略与兜底规则命中。

---

## 七、脚本实现

完整源码见**附录 A**，以下说明关键设计点。脚本针对 BusyBox 环境编写，全程不依赖任何非默认组件。

### 7.1 数据源设计

主用与备用**两个源都抓取**、合并去重，而非"主用失败才切备用"：覆盖最全，单源故障不影响整体，全部源失败才报错退出并保留旧文件。实测两源各 88 条，合并 176 条，去重后 88 条。

```sh
for url in $DERPMAP_URLS; do
  json=$(fetch_one "$url")
  printf '%s' "$json" | extract_ips | add_prefix | validate >> "$TMP_IPS"
done
```

### 7.2 提取管线

下载工具按可用性降级（`curl` → `wget` → `uclient-fetch`），解析同理（`jq` 优先，无则降级为 grep 管线）：

```sh
extract_ips() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.Regions[].Nodes[].IPv4 // empty' 2>/dev/null
  else
    grep -o '"IPv4":"[0-9.]*"' | cut -d'"' -f4
  fi
}
```

这里刻意**不用 `grep -oE`** —— BusyBox grep 在部分精简固件中对扩展正则与 `-o` 的组合支持有问题，`grep -o` + 基础正则 + `cut` 兼容性最好。随后为不带掩码的 IPv4 补 `/32`、做合法性校验，输出按数值排序的纯 CIDR 列表。

### 7.3 安全性设计

| 机制     | 实现                             | 目的              |
| ------ | ------------------------------ | --------------- |
| 阈值保护   | 去重后少于 40 条判定异常，保留旧文件           | 防止接口异常时写坏规则库    |
| 原子写入   | 先写 `.derptmp` 再 `mv` 覆盖        | 避免 Clash 读到半截文件 |
| 自动备份   | 覆盖前 `cp` 为 `.bak`              | 出问题可回滚          |
| 临时文件清理 | `trap 'cleanup' EXIT INT TERM` | 异常退出不留垃圾        |

### 7.4 IPv4 与 IPv6

脚本**只处理 IPv4**，Tailscale实际打洞场景在 v4 下即可解决，输出内容 **100% 来自 Tailscale 官方 derpmap** —— 例如 `172.237.61.190` 出现在结果中，是因为它本身就是 Tailscale sao 区域的真实节点。

### 7.5 幂等性

这是最容易踩的坑，我们需要只比对块内的实际规则内容，当列表无变化时，不写规则文件、不重启Openclash，避免**即使 IP 毫无变化也会每天写文件并重启 OpenClash**：

```sh
awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
  index($0, b) == 1 { inside = 1; next }
  index($0, e) == 1 { inside = 0; next }
  inside && /^- IP-CIDR,/ { print }
' "$CUSTOM_RULES" | sed 's/^- IP-CIDR,//; s/,DIRECT$//' > "$TMP_OLD"

cmp -s "$TMP_OLD" "$TMP_BODY" && { log "列表无变化，不写文件、不重启"; exit 0; }
```

### 7.6 自定义规则文件格式约定

目标文件 `/etc/openclash/custom/openclash_custom_rules.list` 有三条约定：首行必须是 `rules:`；`##-` 前缀的行是注释示例，生效规则要写成 `- 规则,...`；**该文件末行没有换行符**，直接追加会粘连到注释行后面。

因此脚本采取**标记块**策略：用 `##BEGIN tailscale-derp` / `##END tailscale-derp` 圈定自动维护区域，每次先剥离旧块再写新块，用户原有规则完整保留（awk 输出必然换行结尾，顺带修掉了末行无换行的问题）：

```
##BEGIN tailscale-derp   ↓ ↓ ↓ 以下由 tailscale-derp-update.sh 自动维护，勿手工编辑 ↓ ↓ ↓
##updated: 2026-09-04 13:20:15   count: 89
- IP-CIDR,5.161.218.233/32,DIRECT
- IP-CIDR,45.159.97.61/32,DIRECT
...
##END tailscale-derp
```

---

## 八、部署实战

以下在 **Windows 主机**上执行，SSH 连接软路由（`192.168.16.253`）。

### 8.1 生成脚本

按照附录 A：完整脚本的内容保存为 `tailscale-derp-update.sh。

### 8.2 上传脚本

Windows主机向 OpenWrt 传文件：使用 **cmd 的原生文件重定向**，文件句柄直接交给 ssh，字节级透传：

```powershell
cmd /c 'ssh root@192.168.16.253 "cat > /usr/bin/tailscale-derp-update.sh" < "C:\path\to\tailscale-derp-update.sh"'
```

### 8.3 校验文件一致性

这一步不能省，务必确认文件完好：

```powershell
ssh root@192.168.16.253 "chmod +x /usr/bin/tailscale-derp-update.sh && md5sum /usr/bin/tailscale-derp-update.sh && wc -c /usr/bin/tailscale-derp-update.sh && sh -n /usr/bin/tailscale-derp-update.sh && echo TRANSFER_OK"
```

成功时输出 `TRANSFER_OK`，且应为：

```
af996f170aae7f30f2fdea0b9cea5885  /usr/bin/tailscale-derp-update.sh
12938 /usr/bin/tailscale-derp-update.sh
```

md5 对不上说明文件在传输中被损坏，重做 8.2或者采用其他方法上传。

### 8.4 试运行

dry-run 只抓取解析，不写任何文件：

```powershell
ssh root@192.168.16.253 "/usr/bin/tailscale-derp-update.sh -n"
```

预期输出：

```
[13:20:11] 拉取 https://controlplane.tailscale.com/derpmap/default
[13:20:13]   解析到 88 条
[13:20:16] 源可用 2 个 / 失败 0 个；合并前 176 条，去重后 88 条
# ---- 合计 88 条 ----
```

### 8.5 正式运行

```powershell
ssh root@192.168.16.253 "/usr/bin/tailscale-derp-update.sh"
```

脚本完成：写入规则块 → 备份原文件 → 重启 OpenClash 生效，输出 `已更新自定义规则文件 ...（88 条，备份于 ...bak）` 即成功。

### 8.6 验证规则生效

```powershell
ssh root@192.168.16.253 "grep -n 'BEGIN tailscale-derp' /etc/openclash/custom/openclash_custom_rules.list; grep -c '^- IP-CIDR,' /etc/openclash/custom/openclash_custom_rules.list"
ssh root@192.168.16.253 "tailscale netcheck"
```

### 8.7 配置定时自动更新

每日凌晨4:10静默执行（`-q` 仅写系统日志）：

```powershell
ssh root@192.168.16.253 "echo '10 4 * * * /usr/bin/tailscale-derp-update.sh -q' >> /etc/crontabs/root && /etc/init.d/cron restart && echo CRON_OK"
```

得益于幂等设计，IP 列表无变化时不写文件、不重启 OpenClash。

### 8.8 防止刷机丢失

OpenWrt 的 sysupgrade 默认不保留 `/usr/bin` 下自定义文件，加入保留清单：

```powershell
ssh root@192.168.16.253 "echo '/usr/bin/tailscale-derp-update.sh' >> /etc/sysupgrade.conf && echo OK"
```

规则块本身位于 `/etc/openclash/custom/`，属 sysupgrade 保留区，重启与升级均不丢失；只有脚本本体需要上述保护。

---

## 九、达成效果

### 9.1 修复前后对比

| 检查项                         | 修复前               | 修复后                       |
| --------------------------- | ----------------- | ------------------------- |
| `tailscale netcheck` → IPv4 | `(no addr found)` | `yes, 171.xx.xx.xx:6xxx1` |
| `tailscale netcheck` → UDP  | `false`           | `true`                    |

---

## 附录 A：完整脚本

将以下内容保存为 `tailscale-derp-update.sh`，放置于软路由 `/usr/bin/` 目录。

```sh
#!/bin/sh
# ==============================================================================
# tailscale-derp-update.sh  (v4)
# 从 Tailscale 官方 derpmap 的**主用与备用**两个源提取 DERP 节点 IPv4，
# 合并去重后写入 OpenClash，使 DERP/STUN 流量走直连。
#
#   - 仅处理 IPv4，不提取任何 IPv6 地址
#   - 不含任何硬编码/静态地址，输出内容 100% 来自 derpmap
#   - 两个源全部抓取，结果合并去重后写入
#   - 全程使用 BusyBox 兼容语法（不依赖 ERE / mktemp / jq / base64）
#
# 数据源:
#   主用 https://controlplane.tailscale.com/derpmap/default
#   备用 https://login.tailscale.com/derpmap/default
#
# 两种输出模式 (OUTPUT_MODE):
#   custom   写入 /etc/openclash/custom/openclash_custom_rules.list
#            以带标记的规则块形式插入，保留文件里已有的其它规则。
#            不需要注册 rule provider，OpenClash 启动时会把自定义规则前置到
#            整个规则链最前面。老版本 OpenClash 推荐此模式。
#   provider 写入 /etc/openclash/rule_provider/tailscale-derp.list
#            CIDR 列表，供 mihomo 的 rule-provider 引用，可 API 热重载。
#            需先在 OpenClash 里注册 rule provider（UI 或覆写模块）。
#
# 用法:
#   tailscale-derp-update.sh          正常运行（写文件 + 触发重载）
#   tailscale-derp-update.sh -n       只抓取并打印，不写文件（dry-run）
#   tailscale-derp-update.sh -f       写文件后强制重启 OpenClash
#   tailscale-derp-update.sh -q       静默模式（只写 syslog，不打印）
# ==============================================================================

set -u

# --------------------------------- 可调参数 ---------------------------------
DERPMAP_URLS="https://controlplane.tailscale.com/derpmap/default https://login.tailscale.com/derpmap/default"

OUTPUT_MODE="custom"        # custom | provider
CUSTOM_RULES="/etc/openclash/custom/openclash_custom_rules.list"
PROVIDER_DIR="/etc/openclash/rule_provider"
PROVIDER_NAME="tailscale-derp"
PROVIDER_FILE="${PROVIDER_DIR}/${PROVIDER_NAME}.list"

MIN_ENTRIES=40          # 去重后条数低于此值视为数据异常，保留旧文件不动
CONNECT_TIMEOUT=10
MAX_TIME=25

RELOAD_MODE="restart"   # restart=重启 OpenClash | api=调 mihomo API | none=不动作
                        # 注：custom 模式下规则在启动时烘焙进配置，必须靠重启生效
MIHOMO_PORT="9090"      # 仅作兜底；实际端口会自动探测
MIHOMO_SECRET=""        # 留空则自动从 UCI 探测

LOG_TAG="derp-update"

# 自定义规则模式下的块标记（## 是该文件既有的注释前缀，不会被当作规则）
MARK_BEGIN="##BEGIN tailscale-derp"
MARK_END="##END tailscale-derp"
# ---------------------------------------------------------------------------

DRY_RUN=0
QUIET=0

# 临时文件（BusyBox 可能没有 mktemp，做兜底）
TMPDIR_D="${TMPDIR:-/tmp}"
PID_D=$$
TMP_IPS="${TMPDIR_D}/derp-ips.${PID_D}"
TMP_BODY="${TMPDIR_D}/derp-body.${PID_D}"
TMP_STRIP="${TMPDIR_D}/derp-strip.${PID_D}"
TMP_OLD="${TMPDIR_D}/derp-old.${PID_D}"
cleanup() { rm -f "$TMP_IPS" "$TMP_BODY" "$TMP_STRIP" "$TMP_OLD"; }
trap 'cleanup' EXIT INT TERM

say() { [ "$QUIET" -eq 1 ] || echo "[$(date '+%H:%M:%S')] $*"; }
log() { say "$*"; command -v logger >/dev/null 2>&1 && logger -t "$LOG_TAG" "$*"; return 0; }

# 统计文件中的有效行数（grep 无匹配时返回 1，故补 true）
count_lines() { grep -c '[0-9]' "$1" 2>/dev/null || true; }

usage() {
  echo "用法: $0 [-n] [-f] [-q]"
  echo "  -n  dry-run，只打印不写文件"
  echo "  -f  写文件后强制重启 OpenClash"
  echo "  -q  静默，仅写 syslog"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -f|--force)   RELOAD_MODE="restart" ;;
    -q|--quiet)   QUIET=1 ;;
    -h|--help)    usage ;;
    *) echo "未知参数: $1"; usage ;;
  esac
  shift
done

# ------------------------------ 抓取单个源 ------------------------------
# 返回码 0=成功 127=系统无下载工具 其它=该源失败
fetch_one() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" "$url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - -T "$MAX_TIME" "$url" 2>/dev/null
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O - -T "$MAX_TIME" "$url" 2>/dev/null
  else
    return 127
  fi
}

# ------------------------------ 提取 IPv4 ------------------------------
# 只使用 BusyBox 稳支持的 grep -o + BRE + cut，不用 -E
extract_ips() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.Regions[].Nodes[].IPv4 // empty' 2>/dev/null
  else
    grep -o '"IPv4":"[0-9.]*"' | cut -d'"' -f4
  fi
}

# derpmap 的 IPv4 字段不带掩码，统一补 /32
add_prefix() {
  awk '{ if ($0 ~ /\//) print $0; else print $0 "/32" }'
}

# 过滤掉明显非法的条目
validate() {
  awk '
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/ {
      ip = $0; sub(/\/.*/, "", ip)
      n = split(ip, a, ".")
      ok = 1
      for (i = 1; i <= n; i++) if (a[i] + 0 > 255) ok = 0
      if (n == 4 && ok) print
    }'
}

# ------------------------------ 探测 mihomo 控制端口 ------------------------------
detect_port() {
  p=$(uci -q get openclash.config.dashboard_port 2>/dev/null)
  if [ -n "$p" ]; then echo "$p"; return 0; fi

  for f in /etc/openclash/config.yaml /etc/openclash/*.yaml; do
    [ -f "$f" ] || continue
    p=$(sed -n 's/.*external-controller:.*:\([0-9]\{1,5\}\).*/\1/p' "$f" 2>/dev/null | head -1)
    if [ -n "$p" ]; then echo "$p"; return 0; fi
  done

  echo "$MIHOMO_PORT"
}

# ------------------------------ 探测 Dashboard 密钥 ------------------------------
detect_secret() {
  if [ -n "$MIHOMO_SECRET" ]; then echo "$MIHOMO_SECRET"; return 0; fi
  for k in dashboard_password da_password ui_password; do
    s=$(uci -q get "openclash.config.${k}" 2>/dev/null)
    if [ -n "$s" ]; then echo "$s"; return 0; fi
  done
  echo ""
}

# ------------------------------ 触发 OpenClash 重载 ------------------------------
reload_openclash() {
  # custom 模式下规则在启动时烘焙进配置，API 热重载不适用
  if [ "$OUTPUT_MODE" = "custom" ] && [ "$RELOAD_MODE" = "api" ]; then
    say "custom 模式下 API 热重载不适用，改为重启 OpenClash"
    RELOAD_MODE="restart"
  fi

  case "$RELOAD_MODE" in
    none)
      log "RELOAD_MODE=none：等待下次 OpenClash 重启时生效"
      return 0
      ;;
    restart)
      log "重启 OpenClash 使规则生效 ..."
      if /etc/init.d/openclash restart >/dev/null 2>&1; then
        log "OpenClash 已重启"
      else
        log "警告: OpenClash 重启命令返回非零，请手动确认"
      fi
      return 0
      ;;
    api) ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    log "无 curl，跳过 API 热重载"
    return 0
  fi

  port=$(detect_port)
  secret=$(detect_secret)
  url="http://127.0.0.1:${port}/providers/rules/${PROVIDER_NAME}"
  say "调用 API ${url}"

  if [ -n "$secret" ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
             -H "Authorization: Bearer ${secret}" -X PUT "$url" 2>/dev/null)
  else
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
             -X PUT "$url" 2>/dev/null)
  fi

  case "${code:-000}" in
    200|204) log "已通过 API 热重载规则集 ${PROVIDER_NAME} (HTTP ${code})" ;;
    000)     log "API 不可达（端口 ${port}），规则集将在 mihomo 按 interval 重载或下次重启时生效" ;;
    404)     log "API 返回 404：规则集 ${PROVIDER_NAME} 尚未注册，请改用 OUTPUT_MODE=custom 或在 OpenClash 里注册 rule provider" ;;
    *)       log "API 返回 HTTP ${code}，未确认生效；必要时改用 -f 重启 OpenClash" ;;
  esac
}

# ------------------------------ 构造输出内容 ------------------------------
# 参数: $1=去重后的 CIDR 文件  $2=总条数  $3=合并前条数  $4=输出目标
build_output() {
  body="$1"; total="$2"; raw_total="$3"; out="$4"

  if [ "$OUTPUT_MODE" = "custom" ]; then
    # 目标不存在则先建（首行必须是 rules:）
    if [ ! -f "$CUSTOM_RULES" ]; then
      mkdir -p "$(dirname "$CUSTOM_RULES")" || return 1
      echo "rules:" > "$CUSTOM_RULES" || return 1
    fi

    # 剥离上一次写入的块；awk 输出必然以换行结尾，
    # 顺带解决原文件末行可能没有换行符的问题
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      index($0, b) == 1 { skip = 1; next }
      index($0, e) == 1 { skip = 0; next }
      skip { next }
      { print }
    ' "$CUSTOM_RULES" > "$TMP_STRIP" || return 1

    {
      cat "$TMP_STRIP"
      echo "${MARK_BEGIN}   ↓ ↓ ↓ 以下由 tailscale-derp-update.sh 自动维护，勿手工编辑 ↓ ↓ ↓"
      echo "##updated: $(date '+%Y-%m-%d %H:%M:%S')   count: ${total}"
      awk '{ print "- IP-CIDR," $0 ",DIRECT" }' "$body"
      echo "$MARK_END"
    } > "$out" || return 1
  else
    {
      echo "# Tailscale DERP 节点 IPv4 直连规则集 - 由 tailscale-derp-update.sh 自动生成，请勿手工编辑"
      echo "# updated: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "# sources: controlplane.tailscale.com/derpmap/default + login.tailscale.com/derpmap/default"
      echo "# count  : ${total}（合并前 ${raw_total}，已去重）"
      cat "$body"
    } > "$out" || return 1
  fi
  return 0
}

# ------------------------------ 主流程 ------------------------------
main() {
  : > "$TMP_IPS" || { log "错误: 无法创建临时文件 ${TMP_IPS}"; exit 1; }

  ok_sources=0
  failed_sources=0

  for url in $DERPMAP_URLS; do
    say "拉取 ${url}"
    json=$(fetch_one "$url")
    rc=$?

    if [ "$rc" -eq 127 ]; then
      log "错误: 系统里没有 curl / wget / uclient-fetch，无法抓取"
      exit 1
    fi
    if [ "$rc" -ne 0 ] || [ -z "$json" ]; then
      say "  该源无响应，跳过"
      failed_sources=$((failed_sources + 1))
      continue
    fi

    before=$(count_lines "$TMP_IPS")
    printf '%s' "$json" | extract_ips | add_prefix | validate >> "$TMP_IPS"
    after=$(count_lines "$TMP_IPS")
    n=$((after - before))

    if [ "$n" -le 0 ]; then
      say "  该源未解析到任何 IPv4，跳过"
      failed_sources=$((failed_sources + 1))
      continue
    fi

    say "  解析到 ${n} 条"
    ok_sources=$((ok_sources + 1))
  done

  if [ "$ok_sources" -eq 0 ]; then
    log "错误: 全部 derpmap 源均不可用，保持原文件不变"
    exit 1
  fi

  raw_total=$(count_lines "$TMP_IPS")
  grep '[0-9]' "$TMP_IPS" | awk '!seen[$0]++' | \
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n > "$TMP_BODY" || exit 1
  total=$(count_lines "$TMP_BODY")

  say "源可用 ${ok_sources} 个 / 失败 ${failed_sources} 个；合并前 ${raw_total} 条，去重后 ${total} 条"

  if [ "$total" -lt "$MIN_ENTRIES" ]; then
    log "错误: 去重后仅 ${total} 条（阈值 ${MIN_ENTRIES}），判定为数据异常，保留原文件"
    exit 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "# ---- dry-run 输出（未写文件）----"
    if [ "$OUTPUT_MODE" = "custom" ]; then
      awk '{ print "- IP-CIDR," $0 ",DIRECT" }' "$TMP_BODY"
    else
      cat "$TMP_BODY"
    fi
    echo "# ---- 合计 ${total} 条 ----"
    exit 0
  fi

  # custom 模式：先比对"实际规则内容"是否与文件里已有的一致。
  # 不能整体 cmp —— 块里的 updated 时间戳每次都变，否则会天天无谓重启。
  if [ "$OUTPUT_MODE" = "custom" ] && [ -f "$CUSTOM_RULES" ]; then
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      index($0, b) == 1 { inside = 1; next }
      index($0, e) == 1 { inside = 0; next }
      inside && /^- IP-CIDR,/ { print }
    ' "$CUSTOM_RULES" | sed 's/^- IP-CIDR,//; s/,DIRECT$//' > "$TMP_OLD"

    if cmp -s "$TMP_OLD" "$TMP_BODY"; then
      log "DERP 节点列表无变化（${total} 条），不写文件、不重启 OpenClash"
      exit 0
    fi
  fi

  if [ "$OUTPUT_MODE" = "custom" ]; then
    target="$CUSTOM_RULES"
    desc="自定义规则文件"
  else
    mkdir -p "$PROVIDER_DIR" || { log "错误: 无法创建目录 ${PROVIDER_DIR}"; exit 1; }
    target="$PROVIDER_FILE"
    desc="规则集文件"
  fi

  tmp="${target}.derptmp"
  build_output "$TMP_BODY" "$total" "$raw_total" "$tmp" || {
    rm -f "$tmp"; log "错误: 构造${desc}内容失败"; exit 1
  }

  if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    log "内容无变化（${total} 条），不做任何改动"
    exit 0
  fi

  [ -f "$target" ] && cp "$target" "${target}.bak"
  mv "$tmp" "$target" || { log "错误: 写入 ${target} 失败"; exit 1; }

  log "已更新${desc} ${target}（${total} 条，备份于 ${target}.bak）"
  reload_openclash
  exit 0
}

main "$@"
```

---

## 附录 B：常用验证命令

在软路由上或 ssh 软路由执行：

```bash
# 自检：关注 UDP / IPv4 / MappingVariesByDestIP 三项
tailscale netcheck

# 查看连接状态：关注是否 direct
tailscale status

# 测试与远端节点的连通路径
tailscale ping <远端 Tailscale IP>

# 确认规则块位置与条数
grep -n 'BEGIN tailscale-derp' /etc/openclash/custom/openclash_custom_rules.list
grep -c '^- IP-CIDR,' /etc/openclash/custom/openclash_custom_rules.list

# 确认 OpenClash 日志中已无 STUN/DERP 代理条目
logread -e openclash | grep -E '3478|:80' | tail -5
```
