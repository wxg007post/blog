# 版本与关键配置记录

> 用途：以后样式坏了、搜索坏了、CI 红了，**先看这里**，能快速知道"当时是什么环境"。
> 最近更新：2026-09-23（阶段 2 完成后 —— 站点已上线）

## 当前锁定版本

| 项目 | 值 |
|---|---|
| **Hugo** | **0.165.0 extended**（本机 + GitHub Actions 必须一致，见方案 3.5） |
| **Blowfish 主题** | commit **`4643c46bd5e921fee51c420575fadebf9f4b3681`**（2026-09-03，标题 "polish for 3.6"） |
| 主题引入方式 | git submodule，`.gitmodules` 中 `shallow = true`（CI 也用浅克隆） |
| 主题声明的 Hugo 区间 | `extended = true`、`min = 0.162.0`、`max = 0.165.0` |
| 线上地址（当前） | **https://wxg007post.github.io/blog/**（2026-09-23 上线） |
| 自定义域名 | **https://blog.wxgg.eu.cc/**（2026-09-23 已绑定，Cloudflare 代理 + HTTPS） |
| GitHub 仓库 | **https://github.com/wxg007post/blog**（公开） |
| 首次成功部署 | Actions 运行 `35803971748` → **Success**（步骤 42s / 27s / 8s） |
| 提交身份 | `Wang xg <294689316+wxg007post@users.noreply.github.com>` |
| 站内搜索 | Blowfish 内置 **Fuse.js v7.5.0**（完整版，纯客户端） |
| 评论区 | 不做（决策 10） |
| 访问统计 | 不做（决策 11） |
| 图床 | 暂不做，将来 Cloudflare R2（决策 12） |

## 本站覆盖主题的两个文件（**主题升级时必须检查**）

| 文件 | 为什么覆盖 | 改了什么 |
|---|---|---|
| `assets/js/search.js` | 让标签/分类也能被搜到、并改善中文与多词查询 | 加 `useTokenSearch: true`；`keys` 里加 `tags`(0.5) / `categories`(0.3) |
| `layouts/_default/index.json` | 主题默认索引收录了**分类/标签等空列表页**（污染搜索），且**不含 tags/categories** | 只收录 `content/posts/` 下的真实文章；新增 `tags`、`categories` 字段 |

升级主题后请用 `git diff` 比对这两个文件与主题同名文件的差异。

## 阶段 1 验证结果（2026-09-12）

| 项目 | 结果 |
|---|---|
| `hugo` 构建 | ✅ exit=0，35 页，0 报错 |
| 中文计数（CJK） | ✅ 示例文章显示「530 字 · 2 分钟」，**不再出现「1 词 · 1 分钟阅读」** |
| 搜索索引 | ✅ 仅含真实文章（修复前含 `Tags`/`Categories`/`Posts` 等空页） |
| 中文搜索四类查询 | ✅ 连续词 / 带空格多词 / **仅标签** / **仅分类** 全部命中（用主题自带 Fuse 实测） |
| 代码复制按钮 | ✅ `enableCodeCopy = true`；已核实打包后的 `main.bundle.min.*.js` 含 `copy-button` 逻辑，文章页有 5 个代码块容器可供注入 |
| 图片处理 | ✅ 占位封面 PNG 被 Hugo 处理并生成多尺寸变体 |
| 写作模板泄露 | ✅ 已修复（模板目录用 `build.render: never` + `cascade` 排除） |

> 搜索测试脚本：`.research/search-test.cjs`（本地核查用，不提交）

## 阶段 2 验证结果（2026-09-23）

| 项目 | 结果 |
|---|---|
| 仓库 | ✅ `github.com/wxg007post/blog` 公开可访问 |
| Actions | ✅ 运行 `35803971748` **Success** |
| 线上首页 | ✅ 200，标题「时光笔记」，头像与 `/blog/` 路径前缀正常 |
| 样式表 | ✅ `main.bundle.min.*.css` **131 KB 返回 200**（不会白板） |
| 全站页面 | ✅ 首页 / 关于 / 分类 / 标签 / 标签页 / 文章列表 / 404 / sitemap.xml / RSS / index.json 全部 200 |
| 搜索索引 | ✅ 1 条（第一篇文章） |

### 首次运行失败的原因（记下来，换仓库时会再遇到）

```
Setup Pages
HttpError: Not Found - https://docs.github.com/rest/pages/pages#get-a-apiname-pages-site
Get Pages site failed. Please verify that the repository has Pages enabled and configured to build using GitHub Actions
```

**必须在仓库 `Settings → Pages → Source` 里选 `GitHub Actions`**，否则 Actions 无权部署。设置改完后重新推送（或 Re-run all jobs）即可。

### 本地脚本的两个"隐形"要求（踩过）

- `发布前检查.ps1` 必须存成 **UTF-8 with BOM** —— PowerShell 5.1 读无 BOM 的 UTF-8 中文脚本会乱码甚至解析失败；
- `发布前检查.cmd` 必须用 **CRLF** 换行且**只含 ASCII** —— cmd 用 OEM 代码页解码，LF 换行会让它把"半个单词"当命令执行。

### 域名与 baseURL 的关系（**方案 B + 部署后自检**，2026-09-23 定）

本站**不把域名写死在代码里**：CI 构建时由 GitHub Pages 的配置决定站点地址
（`hugo --baseURL "${{ steps.pages.outputs.base_url }}/"`），Pages 未配自定义域名时自动回退到 `https://<用户名>.github.io/<仓库名>`。

| 场景 | 要做什么 | 会不会漏 |
|---|---|---|
| 以后**换域名** | ① Cloudflare 改 DNS ② 仓库 `Settings → Pages` 填新域名 ③ 推送一次触发构建 | **不用改代码**；若忘了第 ③ 步，工作流的「部署后自检」会红掉并打印实际地址 |
| 换仓库名 / 换用户名 | 同上（Pages 地址会自动跟着变） | 同上 |
| 本地预览 | 用 `config/_default/hugo.toml` 的 `baseURL`（当前 `https://blog.wxgg.eu.cc/`），与线上无关 | — |

**为什么会出现"能打开但没样式、图标巨大、头像不显示"？**（2026-09-23 实际踩到）
上一次构建发生在自定义域名生效**之前**，Hugo 把资源路径写成了项目站点子路径 `/blog/css/...`；域名生效后站点挂在**根目录**，浏览器去请求 `https://blog.wxgg.eu.cc/blog/css/...` → 全部 404。**修法：重新构建一次**（新构建会读到域名）。

**部署后自检**（工作流最后一步，自动执行）：实际请求线上首页与它引用的样式表，任一不是 200 就 `exit 1` —— 把"静默发出一个坏站点"变成"CI 立刻报红"，也顺便验证了上面的第 ③ 步有没有漏。

**人工验证方法**（改域名后建议做一次）：打开站点查看源代码，确认 CSS/JS 地址与 `<link rel="canonical">` 都指向新域名、且**不带**旧的项目子路径。

### 部署后发现的 Cloudflare 观察

- 站点响应头含 `server: cloudflare`、`cf-cache-status: DYNAMIC`（HTML 未被缓存，正常）；
- Cloudflare 自动注入了 **Rocket Loader**（`/cdn-cgi/scripts/.../rocket-loader.min.js`）和 Web Analytics beacon。Rocket Loader 会延迟/改写页面 JS，**若发现搜索框或深色模式切换异常，先去 Cloudflare → Speed → Optimization 关掉 Rocket Loader**（这是常见冲突源）。

### 部署后自检的两个细节（2026-09-23 补）

1. **必须带重试**：部署完成后 CDN / GitHub Pages 需要几秒到几十秒才切到新内容。自检只查一次会抓到**上一版** HTML 并误报失败——首次上线时就这样红过一次（站点其实是好的）。现在最多重试 8 次、每次间隔 15 秒，只有连续失败才判红。
2. **baseURL 要强制 https**：Pages 在未启用 "Enforce HTTPS" 时会把 `http://域名` 交给构建。本项目域名走 Cloudflare 代理，**GitHub 无法为该域名签发证书**，所以那个开关一直显示 *Unavailable for your site because your domain is not properly configured to support HTTPS*。不处理的话 Hugo 生成的 `sitemap.xml` / `index.xml` / `og:url` 全是 http（实测 sitemap 4 处、RSS 7 处）。工作流里已把地址统一替换成 https。

> 附带结论：本项目的 HTTPS 由 **Cloudflare 的通用证书**提供（实测签发者 Google Trust Services，`CN=wxgg.eu.cc`，SAN 含 `*.wxgg.eu.cc`，有效期至 2026-10-28），与 GitHub 的 `Enforce HTTPS` 无关——访客侧一切正常。
>
> 若以后确实想要 GitHub 也持有证书并开启 `Enforce HTTPS`：需要按方案 4.1 的顺序补做——把 Cloudflare 那条记录**临时切成"仅 DNS"（灰云）**，等 GitHub 签发证书后勾选 Enforce HTTPS，再切回橙云。期间站点由 GitHub 直连（国内可能变慢），属于可选操作。

## ⚠️ 域名到期日（待你填写）

`wxgg.eu.cc` 是 GNAME 的**免费**域名，续期**必须手动**：到期前 90 天内到 GNAME 活动页领券提交（在域名列表操作或开自动续费**都不生效**）。

- 到期日：**（请到 GNAME 后台查到后填在这里）**
- 建议：设日历提醒（到期前 100 天起、每两周一次）
- 详情见《博客建设方案.md》4.8

## 升级记录

| 日期 | 改了什么 | 结果 |
|---|---|---|
| 2026-09-12 | 初始化：Hugo 0.165.0 + Blowfish `4643c46`（submodule）+ 中文界面 + 站内搜索覆盖 + 代码复制按钮 + 示例文章 | ✅ 本地构建与搜索实测通过 |
| 2026-09-23 | 第一篇文章发布；仓库发布到 GitHub；启用 Pages（Source = GitHub Actions） | ✅ 线上 200，全站页面与样式表验证通过 |
| 2026-09-23 | 绑定自定义域名 `blog.wxgg.eu.cc`（Cloudflare 代理） | ⚠️ 见下方"改域名后必须重新构建" |
