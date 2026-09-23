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

### 域名与 baseURL 的关系（方案 B，2026-09-23 定）

本站**不把域名写死在代码里**：CI 构建时由 GitHub Pages 的配置决定站点地址，并统一规范成 https：

```bash
BASE="${{ steps.pages.outputs.base_url }}"
BASE="${BASE/http:\/\//https:\/\/}"
hugo --gc --minify --baseURL "$BASE/"
```

Pages 未配自定义域名时会自动回退到 `https://<用户名>.github.io/<仓库名>`。

| 场景 | 要做什么 | 会不会漏 |
|---|---|---|
| 以后**换域名** | ① Cloudflare 改 DNS ② 仓库 `Settings → Pages` 填新域名 ③ **推送一次触发构建** | **不用改代码**；但第 ③ 步必须做——CI 已不再做线上自检（见下），漏了只能靠你打开网站发现 |
| 换仓库名 / 换用户名 | 同上（Pages 地址会自动跟着变） | 同上 |
| 本地预览 | 用 `config/_default/hugo.toml` 的 `baseURL`（当前 `https://blog.wxgg.eu.cc/`），与线上无关 | — |

**为什么会出现"能打开但没样式、图标巨大、头像不显示"？**（2026-09-23 实际踩到）
上一次构建发生在自定义域名生效**之前**，Hugo 把资源路径写成了项目站点子路径 `/blog/css/...`；域名生效后站点挂在**根目录**，浏览器去请求 `https://blog.wxgg.eu.cc/blog/css/...` → 全部 404。**修法：重新构建一次**（新构建会读到域名）。

**关于"部署后自检"**：曾经加过一个步骤（请求线上首页与样式表，样式表 404 就判红），但实测 **CI 访问本站会被 Cloudflare 拦（403）**，无法验证线上内容 → **已删除**。原因与完整证据见下面《为什么最终删掉了"部署后自检"》一节。**因此"换域名后重新构建"这一步现在需要靠人工确认。**

**人工验证方法**（改域名后建议做一次）：打开站点查看源代码，确认 CSS/JS 地址与 `<link rel="canonical">` 都指向新域名、且**不带**旧的项目子路径。

### 部署后发现的 Cloudflare 观察

- 站点响应头含 `server: cloudflare`、`cf-cache-status: DYNAMIC`（HTML 未被缓存，正常）；
- Cloudflare 自动注入了 **Rocket Loader**（`/cdn-cgi/scripts/.../rocket-loader.min.js`）和 Web Analytics beacon。Rocket Loader 会延迟/改写页面 JS，**若发现搜索框或深色模式切换异常，先去 Cloudflare → Speed → Optimization 关掉 Rocket Loader**（这是常见冲突源）。

### 部署后的验证方式（2026-09-23 定稿）

1. **构建期断言（保留）**：`Assert asset paths match base URL` 步骤检查 `public/index.html` 引用的样式表路径，是否以当次 baseURL 的路径部分开头（域名 → `/css/`，项目站点 → `/blog/css/`），不符立即失败。**纯本地、不联网、100% 可靠**——这是目前 CI 里唯一的自动防线。
2. **baseURL 强制 https（保留）**：Pages 在未启用 "Enforce HTTPS" 时会把 `http://域名` 交给构建。本项目域名走 Cloudflare 代理，**GitHub 无法为该域名签发证书**，所以那个开关一直显示 *Unavailable for your site because your domain is not properly configured to support HTTPS*。不处理的话 Hugo 生成的 `sitemap.xml` / `index.xml` / `og:url` 全是 http（实测 sitemap 4 处、RSS 7 处）。工作流已把地址统一替换成 https。
3. **不在 CI 里做线上自检（已删除）**：原因见下一节——GitHub 的运行器访问本站会被 Cloudflare 拦（403）。
4. **线上验证靠人工**：发布后用浏览器打开 `https://blog.wxgg.eu.cc/` 看一眼（重点：样式正常、头像与图标显示）。这类问题人眼一眼就能发现。

> 附带结论：本项目的 HTTPS 由 **Cloudflare 的通用证书**提供（实测签发者 Google Trust Services，`CN=wxgg.eu.cc`，SAN 含 `*.wxgg.eu.cc`，有效期至 2026-10-28），与 GitHub 的 `Enforce HTTPS` 无关——访客侧一切正常。
>
> 若以后确实想要 GitHub 也持有证书并开启 `Enforce HTTPS`：需要按方案 4.1 的顺序补做——把 Cloudflare 那条记录**临时切成"仅 DNS"（灰云）**，等 GitHub 签发证书后勾选 Enforce HTTPS，再切回橙云。期间站点由 GitHub 直连（国内可能变慢），属于可选操作。

### 为什么最终删掉了"部署后自检"（完整证据链，2026-09-23）

**一句话结论**：GitHub Actions 的运行器访问本站会被 **Cloudflare 返回 403**（实测拿到 5295 字节的拦截页），因此 CI **看不到**线上真实内容 → 线上自检在 CI 里不可能有效，故删除。

| 步骤 | 证据 | 结论 |
|---|---|---|
| ① 为什么连续三次红？ | deploy 作业耗时跳变：#4 12 秒 / #5 1 分 4 秒 / #6 9 秒 / #7 9 秒；且 #7 的注解里**没有**我预期的诊断文字 | 脚本**半路被终止**：GitHub 的 `run:` 默认以 `bash -e` 执行，我又写了 `set -o pipefail`，未兜底的 `grep … \| head …` 与 `curl` 一旦返回非零就立即退出 → 重试与诊断代码都没机会执行 |
| ② 修好脚本后为何是"警告"而非"通过"？ | 注解原文：`首页返回 403，页面 5295 字节；目标 http://blog.wxgg.eu.cc/ ；共尝试 6 次` | **Cloudflare 拦截了 GitHub 运行器的 IP**（Azure 云主机段）。已排除的假设：UA 问题（四种 UA 从本机访问均 200）、`page_url` 输出名问题（v4/v5 均正确） |
| ③ 那还留不留？ | 403 会让自检永远停在"环境无法验证" | 无法验证 = 没有保护价值，只会每轮留一条警告 → **删除**；构建侧改由不联网的"构建期断言"护航 |

**三条教训（写给未来的自己）**：

1. CI 脚本里，**"自己的错误处理"必须先于"环境异常处理"**——否则后者永远不会生效；
2. **"预期会出现的诊断没出现"本身就是证据**：说明脚本比你以为的更早就死了；
3. 本环境限制：**agent 读不到 GitHub 的运行日志与 API**（注解正文是前端渲染，HTML 里没有；API 匿名限流在这条共享出口 IP 上长期为 0）→ 需要诊断时，请把运行页面上注解的文字**复制给 agent**。

## ⚠️ 域名到期日（待你填写）

`wxgg.eu.cc` 是 GNAME 的**免费**域名，续期**必须手动**：到期前 90 天内到 GNAME 活动页领券提交（在域名列表操作或开自动续费**都不生效**）。

- 到期日：**（请到 GNAME 后台查到后填在这里）**
- 建议：设日历提醒（到期前 100 天起、每两周一次）
- 详情见《博客建设方案.md》4.8（本地文档，未随仓库发布）

## 升级记录

| 日期 | 改了什么 | 结果 |
|---|---|---|
| 2026-09-12 | 初始化：Hugo 0.165.0 + Blowfish `4643c46`（submodule）+ 中文界面 + 站内搜索覆盖 + 代码复制按钮 + 示例文章 | ✅ 本地构建与搜索实测通过 |
| 2026-09-23 | 第一篇文章发布；仓库发布到 GitHub；启用 Pages（Source = GitHub Actions） | ✅ 线上 200，全站页面与样式表验证通过 |
| 2026-09-23 | 绑定自定义域名 `blog.wxgg.eu.cc`（Cloudflare 代理） | ⚠️ 见《域名与 baseURL 的关系》一节 |
| 2026-09-23 | 私人工作文档（建设方案/操作手册/标签清单/发布前检查脚本）取消 git 跟踪，只放本地；`content/.obsidian/` 的本机配置同样取消跟踪 | ✅ 本地文件原地保留，脚本照常可用；仓库已跟踪文件 39 → 31 |
