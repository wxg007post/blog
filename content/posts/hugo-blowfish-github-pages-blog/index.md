---
title: "用 Hugo + Blowfish 在 GitHub Pages 上搭一个中文博客"
date: 2026-09-23T08:48:17+08:00
lastmod: 2026-09-23
draft: false
slug: "hugo-blowfish-github-pages-blog"
description: "从零搭起这个博客的完整过程：为什么选 Hugo + Blowfish、怎么做到推送即上线，以及踩到的一堆坑——搭建期的 8 个，加上绑定自定义域名后才暴露的 3 个（基地址没跟上域名、Pages 未启用、绝对地址全是 http）。"
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

## 搭建期间踩到的 8 个坑

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

## 上线之后才暴露的 3 个问题

"本地能跑"和"挂到自己的域名上一切正常"是两件事。下面这三个，都是**绑定自定义域名之后**才冒出来的。

### 问题 1：域名绑好了，页面却"没样式"（基地址没跟上域名）

**现象**：`https://blog.wxgg.eu.cc/` 能打开、文字都在，但**完全没有样式**——SVG 图标撑成巨大的一坨、头像不显示、布局全乱。

**排查**：查看页面源代码，两个线索立刻暴露问题：

- `<link rel="canonical">` 指向的是 `https://<用户名>.github.io/blog/`，而不是我的域名；
- 所有静态资源都是**根相对路径** `/blog/css/...`——站点现在挂在**域名根目录**，浏览器于是去请求 `https://blog.wxgg.eu.cc/blog/css/...`，**全部 404**。

**根因**：Hugo 生成资源路径用的是 `baseURL`，而我在工作流里让它取 GitHub Pages 的自动地址：

```yaml
hugo --minify --baseURL "${{ steps.pages.outputs.base_url }}/"
```

**这份 HTML 是在自定义域名生效之前构建的**。那时 Pages 给出的地址还是 `https://<用户名>.github.io/blog`，Hugo 就把 `/blog/` 写进了每一个资源路径；域名生效后站点换到根目录，路径全部对不上。

**修法**（两条路，我最后选了后者）：

| 做法 | 换域名时要做什么 | 优缺点 |
|---|---|---|
| 把域名写死在 `hugo.toml` 的 `baseURL` | 改 1 行配置 + 重新构建 | 确定、直观，但容易忘 |
| 继续用 Pages 的地址，但**构建前统一规范成 https**，并加部署后自检 | **只改 Pages 设置**，代码不用动 | 自适应；万一漏了也会被自检拦住 |

**最关键的一句**：不管走哪条路，**绑域名/换域名之后都必须重新构建一次**。因为 canonical、sitemap、RSS 这些绝对地址本来就是跟着域名走的，不重建就不会更新——我这次就是"域名先生效、构建是上一次的产物"，才出现"能打开但没样式"。

### 问题 2：Pages 没启用，工作流直接报 HttpError

第一次运行 Actions 就红了，报错原文：

```
Setup Pages
HttpError: Not Found - https://docs.github.com/rest/pages/pages#get-a-apiname-pages-site
Get Pages site failed. Please verify that the repository has Pages enabled and configured to build using GitHub Actions
```

**根因**：仓库还没启用 Pages。Actions 想替你部署，但 Pages 功能没开，它去查 Pages 站点时拿到 404。

**修法**：仓库 `Settings → Pages → Build and deployment → Source` 选 **GitHub Actions**。报错其实写得很清楚，但如果没注意到那个 "Source" 下拉框，很容易误以为是自己工作流写错了。

### 问题 3：站点的绝对地址全是 http

修好前两个问题后，我去检查 `sitemap.xml` 和 RSS，发现里面的链接**全是 `http://`**（sitemap 4 处、RSS 7 处），`og:url` 也是 http。

**根因**：Pages 在**没有启用 "Enforce HTTPS"** 时，会把 `http://域名` 交给构建，Hugo 就照着生成了所有绝对地址。

有意思的是，那个开关我**想勾也勾不上**，GitHub 提示：

> Unavailable for your site because your domain is not properly configured to support HTTPS

因为域名在 Cloudflare 上开着**代理（橙色云）**，GitHub 无法为它签发自己的证书，所以这个开关一直不可用。**但这不影响访客**：HTTPS 由 Cloudflare 的证书提供（实测签发者是 Google Trust Services，覆盖 `*.wxgg.eu.cc`，有效期到 2026-10-28）。

**修法**：构建前把拿到的地址统一替换成 https：

```bash
BASE="${BASE/http:\/\//https:\/\/}"
hugo --minify --baseURL "$BASE/"
```

改完 sitemap / RSS / og:url 全部变成 https。（文件里剩下的 `http://www.sitemaps.org/...` 是 XML 命名空间，属于正常现象。）

## 我给自己加的两道保险

这些坑有个共同点：**页面"看起来是好的"**，靠人眼很容易漏。所以我加了两道自动检查。

**① 部署后自检**：构建部署完成后，自动请求线上首页和它引用的样式表，**任一不是 200 就把这次运行判为失败**。这样"地址不一致导致没样式"会变成 CI 上的红叉，而不是等我偶然发现。

这里有个真实的教训：**自检必须带重试**。我第一版只检查一次，结果部署刚结束、CDN 还没切到新内容，它抓到的是**上一版** HTML，于是误报失败——站点其实已经好了。

**② 发布前检查**：推送前跑一个脚本，扫内容里有没有真实密钥或内网 IP、有没有引用不存在的图片（坏图）、有没有超过 500KB 的大图。它分两档：`.md` 文档里出现 `sk-`、`AKIA` 这类**格式说明**只算"提示"（否则每篇教程都会报警），而配置文件里出现同样特征就直接算"高危"。

## 顺手的几个小设置

- **文章模板**：把 front matter 固化成模板，新建文章时不用手填；
- **图片规范**：统一 WebP、宽度 ≤1600px、和文章放同一目录；
- **发布前检查**：写个脚本，推送前扫一遍"有没有真实密钥、有没有坏图、有没有超过 500KB 的大图"；
- **版本记录**：把 Hugo 版本、主题 commit 记进一个文件，以后样式坏了能快速回退。

## 小结

这套方案真正的好处不是"免费"，而是**整条链路都是纯文本 + 可迁移的**：文章是 Markdown，仓库是 Git，构建靠云端。哪怕以后想换框架或换托管，`content/` 目录里的东西一个字都不用改。

写这篇的时候，博客刚上线。上线之后我又陆续发现并修掉了几个问题（见上面那节），也算印证了一件事：**静态博客的坑大多不在"搭"，而在"域名、协议、缓存"这些边界上**。

接下来就是慢慢往里填内容了——毕竟搭博客只是手段，**持续记录才是目的**。

## 更新记录

| 日期 | 变更 |
|---|---|
| 2026-09-23 | 初稿发布 |
| 2026-09-23 | 补充「上线之后才暴露的 3 个问题」与「两道保险」——绑定自定义域名后踩到的 |

---

*本文里的 IP、密钥、订阅链接等一律用占位符表示（如 `192.168.x.x`、`YOUR_TOKEN`），请按自己的环境替换。*
