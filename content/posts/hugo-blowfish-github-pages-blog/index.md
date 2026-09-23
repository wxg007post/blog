---
title: "用 Hugo + Blowfish 在 GitHub Pages 上搭一个中文博客"
date: 2026-09-23T08:48:17+08:00
lastmod: 2026-09-23
draft: false
slug: "hugo-blowfish-github-pages-blog"
description: "从零搭起这个博客的完整过程：为什么选 Hugo + Blowfish、怎么做到推送即上线，以及我实际踩到的 8 个坑（版本锁定、中文搜索、头像目录、白板问题……）。"
categories: ["折腾记录"]
tags: ["Hugo", "GitHub Pages"]
showHero: true
heroStyle: "big"
showTableOfContents: true
showTaxonomies: true
---

这是本站的第一篇文章。与其写"Hello World"，不如把**搭这个博客的过程**记下来——既能帮到想做同样事情的人，也能让我下次重装时不用再搜一遍。

## 我想要的是什么

| 需求 | 原因 |
|---|---|
| 用 Markdown 写作 | 不想为了写篇文章去点富文本编辑器 |
| 推送即上线 | 不想登服务器、不想手动上传 |
| 0 成本 | 个人博客不值得为它付服务器钱 |
| 自己的域名 | 将来换托管平台时链接不作废 |
| 中文显示和搜索正常 | 很多静态博客主题在这两点上是坏的 |

## 技术选型

**静态站点生成器：Hugo。** 对比过 Hexo 和 Astro：

- **Hugo**：一个 exe 文件、零依赖、构建毫秒级，主题多且维护规范；
- **Hexo**：中文教程最多，但要装 Node + 一堆 npm 插件，插件和新版 Node 偶尔打架；
- **Astro**：主题最好看，但依赖多、迭代快，教程容易过期。

**主题：Blowfish。** 深色模式、分类标签、站内搜索、代码复制按钮都是原生支持，中文文档齐全。

**托管：GitHub Pages + Cloudflare。** 静态文件放在 GitHub 免费托管，前面套一层 Cloudflare 做 CDN——因为国内直连 GitHub Pages 的裸地址经常很慢。

整体链路是这样的：

```
本地写 Markdown  →  git push  →  GitHub Actions 自动构建
                                        ↓
        Cloudflare（CDN/HTTPS）  ←  GitHub Pages（静态文件）
```

日常只有两个动作：**写 .md 文件**、**点一下推送**。构建在云端完成，本地不需要装编译环境。

## 搭建步骤

### 1. 装 Hugo（版本必须锁死）

这是第一个坑，先说结论：**Hugo 不能装最新版**。

Blowfish 在主题配置里声明了它能接受的版本区间（我这份是 `min = 0.162.0`、`max = 0.165.0`）。装一个比 `max` 更新的版本，Hugo 会因为不满足主题声明而**直接报错退出**——不是"可能有问题"，是构建失败。

所以做法是：**手动下载指定版本的压缩包 + 校验 SHA256 + 解压到固定目录 + 加进 PATH**。

```powershell
# 本机安装（Windows）
# 1) 下载指定版本
#    https://github.com/gohugoio/hugo/releases/download/v0.165.0/hugo_extended_0.165.0_windows-amd64.zip
# 2) 校验（下载页会给出 SHA256，务必对一遍）
Get-FileHash .\hugo_extended_0.165.0_windows-amd64.zip -Algorithm SHA256
# 3) 解压出 hugo.exe 放到固定目录，并把该目录加入用户 PATH
# 4) 验证：必须带 +extended
hugo version
# hugo v0.165.0+extended windows/amd64
```

> 网页上 "extended" 版本是必须的——主题配置里写了 `extended = true`。

### 2. 用 submodule 引入主题

```bash
git init -b main
git submodule add --depth 1 -b main \
  https://github.com/nunocoracao/blowfish.git themes/blowfish
```

**为什么用 submodule 而不是直接把主题文件复制进来**：主仓库里只保存一个"指针"（记录主题的 commit），主题那一大堆文件不会进你的仓库。我这份主题的完整历史接近 90 MB，而我的博客仓库只有几百 KB。升级主题时也只是一条命令。

### 3. 配置：中文、搜索、代码复制

Blowfish 的配置**放在 `config/_default/` 下的多个文件里**，不是根目录一个 `hugo.toml`（这一点跟着网上旧教程做很容易踩空）。几个关键项：

```toml
# config/_default/hugo.toml
baseURL = "https://你的域名/"
defaultContentLanguage = "zh-cn"
timeZone = "Asia/Shanghai"      # 不写的话日期可能按 UTC 走，差 8 小时
hasCJKLanguage = true           # 中文按字统计字数与阅读时间
mainSections = ["posts"]        # 明确"文章区"，避免关于页混进文章流
summaryLength = 70
```

```toml
# config/_default/params.toml
enableSearch = true             # 站内搜索
enableCodeCopy = true           # 代码块复制按钮
```

### 4. 自动部署

在仓库里放一个 GitHub Actions 工作流（`.github/workflows/deploy.yml`），推送到 `main` 就自动构建并发布。三个关键参数：

| 参数 | 作用 | 不写的后果 |
|---|---|---|
| `submodules: recursive` | 把主题 submodule 一起拉下来 | `themes/blowfish` 是空目录，构建失败 |
| `fetch-depth: 0` | 拉完整提交历史 | 文章的"最后更新"时间不准 |
| `--baseURL "${{ steps.pages.outputs.base_url }}/"` | 让 GitHub 自动给出站点地址 | 项目站点会因地址带子路径而样式全丢 |

最后别忘了在仓库 **Settings → Pages → Source** 里选 **GitHub Actions**——不选的话工作流会在部署那步报 `HttpError: Not Found`。

## 我实际踩到的 8 个坑

| # | 现象 | 原因 | 解决 |
|---|---|---|---|
| 1 | 构建直接失败 | Hugo 版本超出主题声明的 `max` | 锁定主题支持的版本，别装最新版 |
| 2 | CI 里装 Hugo 那步 404 | `.deb` 资产名写成了 `Linux-64bit` | 实际是 `linux-amd64.deb`（小写） |
| 3 | 文章页显示「1 词 · 1 分钟阅读」 | 没开 `hasCJKLanguage`，整段中文被当成一个"词" | 开启后按字统计 |
| 4 | 首页有头像，但**整个站点构建失败** | 头像放进了 `static/`，而主题用 `resources.Get` 从 `assets/` 取图 | 头像放 `assets/img/` |
| 5 | 搜标签名搜不到文章 | 主题的搜索索引**不含 tags/categories**，而且混进了分类页、标签页这类空页面 | 覆盖索引模板，只收录真实文章并加上这两个字段 |
| 6 | 线上"页面能打开但样式全丢" | `baseURL` 和真实地址不一致（项目站点带 `/仓库名/` 子路径） | 让 `baseURL` 指向真实地址，工作流里用 `pages` 的输出 |
| 7 | 以为草稿是"私密"的 | `draft: true` 只是不构建，**文件本身仍在公开仓库里** | 敏感内容从一开始就不要写进仓库 |
| 8 | 本地图片正常、线上裂图 | Obsidian 默认写 Wiki 链接 `![[图.jpg]]`，Hugo 不认 | 关掉 Wiki 链接，新链接格式改成相对路径 |

其中两个值得多说一句：

**坑 2 的教训**：那个错误的文件名是我从主题自己的 CI 配置里抄来的——**"别人的 CI 里这么写"不等于"一定能用"**。最后是把两个候选文件名都请求一遍（一个 404、一个 200）才确定的。凡是涉及具体版本号、文件名的东西，**下载一次比读十篇教程都可靠**。

**坑 5 的教训**：搜索是静态博客最容易"看起来有、其实没有"的功能。判断它有没有用，不能看配置文件里写没写 `enableSearch = true`，而要**实际搜几个中文词**：连续词、带空格的多词、标签名、分类名。我是搜"标签名"时发现搜不到的——因为索引里根本没有这个字段。

## 顺手的几个小设置

- **文章模板**：把 front matter 固化成模板，新建文章时不用手填；
- **图片规范**：统一 WebP、宽度 ≤1600px、和文章放同一目录；
- **发布前检查**：写个脚本，推送前扫一遍"有没有真实密钥、有没有坏图、有没有超过 500KB 的大图"；
- **版本记录**：把 Hugo 版本、主题 commit 记进一个文件，以后样式坏了能快速回退。

## 小结

这套方案真正的好处不是"免费"，而是**整条链路都是纯文本 + 可迁移的**：文章是 Markdown，仓库是 Git，构建靠云端。哪怕以后想换框架或换托管，`content/` 目录里的东西一个字都不用改。

写这篇的时候，博客刚上线。接下来就是慢慢往里填内容了——毕竟搭博客只是手段，**持续记录才是目的**。

---

*本文里的 IP、密钥、订阅链接等一律用占位符表示（如 `192.168.x.x`、`YOUR_TOKEN`），请按自己的环境替换。*
