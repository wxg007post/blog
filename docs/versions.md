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
| 自定义域名 | `https://blog.wxgg.eu.cc/`（阶段 3 绑定；`baseURL` 已按此配置） |
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
