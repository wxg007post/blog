---
# ⚠️ 这是「新建文章模板」。用 `hugo new posts/文章名/index.md` 建文章时会自动套用。
# 用 Obsidian 写作的话，请用 content/_templates/文章模板.md 那份（内容一样）。
title: ""
date: {{ .Date }}
lastmod: {{ .Date }}
draft: true                 # true = 草稿，本地预览能看到、不会发布；写完脱敏检查后再改 false
description: ""             # 一句话说清这篇解决了什么问题（会进搜索结果和分享卡片）
categories: ["折腾记录"]     # 只有两个分类：折腾记录 / 攻略
tags: []                    # 最多 5 个；写法要统一（Docker 不要写成 docker）
# featureimage: "feature.webp"   # 可选：不写也行，主题会自动找同目录的 feature.* 图片
showHero: true              # 正文顶部是否显示大图
heroStyle: "big"            # basic / big / background / thumbAndBackground
showTableOfContents: true   # 右侧目录
showTaxonomies: true        # 文章头部显示分类 / 标签徽章
series: []                  # 系列文章用（需先在 hugo.toml 的 [taxonomies] 注册，已注册好）
series_order: 0
---

<!-- 写正文。推荐骨架（详见《博客建设方案.md》5.4 节）：

【教程型】目标 → 前提条件 → 步骤（带命令/截图）→ 验证方法 → 如何回滚
【踩坑型】现象 → 排查过程 → 根因 → 解决方案 → 如何避免
【攻略型】结论先行 → 数据/表格 → 分情况建议 → 更新日期与版本号

⚠️ 脱敏提醒：内网 IP 写成 192.168.x.x、密钥写成 YOUR_TOKEN、截图里的后台信息要打码。
-->
