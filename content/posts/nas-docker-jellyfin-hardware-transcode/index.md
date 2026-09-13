---
title: "群晖 Docker 部署 Jellyfin 并开启硬件转码"
date: 2026-09-12T20:30:00+08:00
lastmod: 2026-09-12
draft: true
description: "示例文章：用 Docker 在群晖上部署 Jellyfin，并正确启用硬件转码的完整过程。"
categories: ["折腾记录"]
tags: ["NAS", "Docker", "Jellyfin", "硬件转码"]
showHero: true
heroStyle: "big"
showTableOfContents: true
showTaxonomies: true
---

> **这是一篇示例文章**（`draft: true`，只在本机预览可见，不会发布到线上）。
> 它的作用是给你一个可以照抄的结构——写自己的文章时把内容换掉、把 `draft` 改成 `false` 即可。

## 目标

在群晖上用 Docker 跑起 Jellyfin，并让它在播放时**使用核显硬件转码**，而不是靠 CPU 硬扛。

## 前提条件

| 项目 | 要求 |
|---|---|
| 群晖型号 | 带 Intel 核显的型号（示例） |
| DSM 版本 | 7.x |
| Docker | Container Manager 已安装 |
| 目录 | `/volume1/docker/jellyfin`（示例路径） |

## 步骤

### 1. 建立目录

```bash
mkdir -p /volume1/docker/jellyfin/config
mkdir -p /volume1/docker/jellyfin/cache
```

### 2. 确认核显设备节点存在

```bash
ls -l /dev/dri
# 期望看到 card0 与 renderD128
```

### 3. 用 docker compose 启动

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    devices:
      - /dev/dri:/dev/dri        # 把核显直通进容器，硬件转码的关键
    volumes:
      - /volume1/docker/jellyfin/config:/config
      - /volume1/docker/jellyfin/cache:/cache
      - /volume1/media:/media:ro
    ports:
      - "8096:8096"
    restart: unless-stopped
```

```bash
docker compose up -d
```

### 4. 在 Jellyfin 后台开启硬件转码

进入 Jellyfin 控制台 → 播放 → 转码：

- 硬件加速选 **Intel QuickSync (QSV)**
- 勾选需要转码的编码格式
- 保存后播放一个高码率视频，观察 CPU 占用是否明显下降

## 验证

- [ ] `docker logs jellyfin` 无报错
- [ ] 后台能看到 QSV 选项（没有的话通常是 `/dev/dri` 没直通成功）
- [ ] 播放时 CPU 占用低于 30%（示例阈值）

## 如何回滚

```bash
docker compose down
```

删除 `/volume1/docker/jellyfin` 目录即可完全恢复。

## 小结

- 关键就一句：**`devices: - /dev/dri:/dev/dri` 不写，Jellyfin 后台就不会出现 QSV 选项**。
- 若主机是 AMD 核显，对应的是 VAAPI，节点同样是 `/dev/dri`。

---

*写自己的文章时，记得把示例里的路径、版本号换成自己的；内网 IP 一律写成 `192.168.x.x`。*
