---
name: ra81-immortalwrt-openclash
description: Flash a Redmi AX3000 (RA81, IPQ5000, 128MB NAND, dual rootfs slots) from stock Xiaomi firmware to ImmortalWrt + OpenClash, keeping the stock system as a fallback; put the oversized mihomo core on the spare mtd20 "overlay" partition; then configure an OpenClash subscription. Use when the user wants to flash/repair/roll back RA81 (Redmi AX3000) firmware, build a slim OpenClash image for a small-flash Xiaomi/Redmi router, or debug OpenClash on such a router (nodes unreachable, DNS, cron). Trigger on "RA81", "Redmi AX3000 刷机", "ImmortalWrt OpenClash 小闪存", "mtd18/mtd19 启动槽", "flag_boot_rootfs".
---

# Redmi AX3000 (RA81) → ImmortalWrt + OpenClash

> **仅供学习研究。** 刷机有变砖风险，后果自负。全程不写 U-Boot、ART、bdata，原厂系统始终保留在另一个启动槽。

## 0. 先建立事实，不要凭印象

在路由器上（原厂系统）只读确认，任何一项对不上就停：

```sh
cat /proc/cmdline                    # ubi.mtd=rootfs_1 → 当前跑在 mtd19
cat /sys/class/ubi/ubi0/mtd_num      # 19
cat /proc/mtd                        # mtd18 "rootfs" / mtd19 "rootfs_1" 各 0x2400000(36MiB)；mtd20 "overlay" 0x1f00000(31MiB)
for k in flag_boot_rootfs flag_last_success flag_try_sys1_failed flag_try_sys2_failed; do echo $k=$(nvram get $k); done
df -h /tmp; free                     # /tmp 是内存，约 89MB
```

**写入目标永远是“当前没在运行的那个槽”。** 下文假设运行在 mtd19，写 mtd18；如果相反，全部对调（`flag_boot_rootfs` 0=mtd18，1=mtd19）。

## 1. 前置条件（缺一不可）

- 原厂 SSH 已解锁（社区工具 XMiR-Patcher，按其文档操作；本 skill 不覆盖这一步）。
- **全部 mtd 分区已备份到电脑并校验 md5**，尤其 ART（mtd13，无线校准）、bdata（mtd15）、APPSBL。
  - ⚠️ 逐个分区 `dd` → 传走 → 删除。**不要一次性把所有分区 dump 到 `/tmp`**：`/tmp` 是内存，三个 36/36/31MiB 分区就会把它写满，SSH 随之被 OOM 杀掉。
- 原厂恢复包就位：`MIWIFIRepairTool` + RA81 原厂 `.bin`，放在一台能接网线的 Windows 上。
- 记下宽带 PPPoE 账号密码、WiFi 名称密码（刷完全部丢失）。
- **人在路由器旁，备一根网线。** 远程控制机若靠 WiFi 连这台路由器，刷机瞬间所有远程通道都会断。

## 2. 空间核算（为什么要这样做）

| 项目 | 数值 |
|---|---|
| 单个系统槽 | 36MiB = 288 PEB；扣 UBI 开销约 264 LEB × 124KiB ≈ 32MiB |
| kmiit 内核卷 | 43 LEB（5.2MiB） |
| rootfs + OpenClash + ruby 等依赖（xz squashfs） | 124 LEB（约 15MiB） |
| mihomo 官方 arm64 | 57MB，xz 后 13.6MB |
| 自编去 gVisor 版 | 47MB，xz 后 11.4MB——**仍放不下** |

结论：系统槽只放 OpenClash + 依赖，**内核放到 mtd20**（UBIFS 卷 `ocdata`，开机由 `/etc/init.d/ocdata`（S11）挂到 `/etc/openclash`）。代价：mtd20 原是原厂 `/data`，切回原厂后原厂设置会恢复出厂（可用备份写回）。

镜像里**没有 xz 解压**，内核必须用 gzip 交付。

## 3. 刷入（写空闲槽）

```sh
scp -O fw.ubi root@192.168.31.1:/tmp/          # 原厂 dropbear 无 sftp，scp 要 -O
# 原厂 SSH 只有 ssh-rsa：-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa
openssl dgst -sha256 /tmp/fw.ubi               # 原厂没有 sha256sum
[ "$(cat /sys/class/ubi/ubi0/mtd_num)" = 19 ] || exit 1      # 守卫：确认没在跑 mtd18
grep -q 'mtd18: 02400000 00020000 "rootfs"' /proc/mtd || exit 1
ubiformat /dev/mtd18 -y -f /tmp/fw.ubi
# 可选验证：只读挂一下看卷
ubiattach -m 18 -d 5 && ubinfo -d 5 -a | grep Name; ubidetach -d 5
nvram set flag_boot_rootfs=0
nvram set flag_last_success=0
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram commit
reboot
```

首启 3–5 分钟（初始化 rootfs_data、WiFi、拨号）。

## 4. 首启验证

```sh
cat /etc/openwrt_release; cat /sys/class/ubi/ubi0/mtd_num   # ImmortalWrt，18
fw_printenv flag_boot_rootfs                                # 必须读到 0 —— 证明原厂 nvram 与 U-Boot env 是同一存储（/etc/fw_env.config → /dev/mtd10 APPSBLENV），回退通道可用
ifstatus wan; ping -c1 baidu.com
```

## 5. 初始化 mtd20 并放入内核

用 `router/init-mtd20-ocdata.sh`（只认名为 `overlay` 的 mtd，内核 sha 不符就中止）：

```sh
scp -O clash_meta.gz init-mtd20-ocdata.sh root@<router>:/tmp/
sh /tmp/init-mtd20-ocdata.sh && reboot
# 重启后：
mount | grep ocdata            # ubi1:ocdata on /etc/openclash type ubifs
/etc/openclash/core/clash_meta -v
```

## 6. 配订阅并启动 OpenClash（uci，无需 LuCI）

```sh
S=$(uci add openclash config_subscribe)
uci set openclash.$S.enabled=1 openclash.$S.name=sub openclash.$S.sub_ua=clash.meta openclash.$S.sub_convert=0
uci set openclash.$S.address='<订阅地址>'
uci set openclash.config.config_path=/etc/openclash/config/sub.yaml
uci commit openclash
sh /usr/share/openclash/openclash.sh          # 下载订阅；busybox 没有 timeout 命令，别包 timeout
uci set openclash.config.enable=1; uci commit openclash
/etc/init.d/openclash restart
```

**国内必改 DNS**：订阅没带 `dns:` 时 OpenClash 自动补的 fallback 是 dns.google / cloudflare DoH，国内不通 → 节点域名解析失败 → 所有代理超时。

```sh
uci set openclash.config.enable_custom_dns=1
# 关掉 group=fallback 且 ip 为 dns.google/dns-query、dns.cloudflare.com/dns-query 的条目
uci show openclash | grep -B3 -E "dns.google/dns-query|dns.cloudflare.com/dns-query"   # 找到索引后：
uci set openclash.@dns_servers[N].enabled=0
uci commit openclash; /etc/init.d/openclash restart
```

**每日自动更新订阅**：

```sh
uci set openclash.config.auto_update=1 openclash.config.config_auto_update_mode=0
uci set openclash.config.auto_update_time=4 openclash.config.config_update_week_time='*'
uci commit openclash; /etc/init.d/openclash restart
grep openclash /etc/crontabs/root             # 0 4 * * * /usr/share/openclash/openclash.sh
pidof crond || /etc/init.d/cron restart       # 开机时 crontab 为空则 crond 不会启动，需手动拉起一次
```

验证（重启 OpenClash 后**等 “Start Successful” 再测**，否则会误判失败）：

```sh
tail -1 /tmp/openclash.log
curl -s -o /dev/null -w "%{http_code}\n" -x http://<user>:<pass>@127.0.0.1:7893 https://www.google.com   # 认证见 /etc/openclash/<cfg>.yaml 的 authentication
# 查失败原因：curl -N -H "Authorization: Bearer $(uci get openclash.config.dashboard_password)" "http://127.0.0.1:9090/logs?level=debug"
```

## 7. 回退

1. 新系统能进：`fw_setenv flag_boot_rootfs 1; reboot` → 回原厂（约 3 分钟）。
2. 新系统进不去：网线接 LAN，`MIWIFIRepairTool` + 原厂 `.bin`，按住 reset 通电，TFTP 刷回（10–20 分钟）。
3. U-Boot 坏（本流程不写它）：拆机 TTL 串口。

## 8. 构建镜像

见仓库 `build/01…04`：在 Debian 容器里解开 kmiit 的 factory.ubi，往 rootfs 里注入离线 ipk（kmod 必须来自 kmiit feed、内核哈希一致）和去掉面板/GeoSite 的 OpenClash，补 `S99openclash`/`K15openclash`/`S11ocdata` 链接（手工解包不跑 postinst），`mksquashfs -comp xz -b 256K`，`ubinize -p 128KiB -m 2048 -s 2048`，`rootfs_data` 设 `autoresize`。

**发布镜像前必须扫一遍隐私**：`grep -rIl -E "<PPPoE密码>|<WiFi密码>|<订阅域名>" rootfs/`，`/etc/shadow` 的 root 字段应为空；自定义首启脚本只用于私有构建。

## 自动化执行时的注意点

- 非交互输密码：`SSH_ASKPASS=<脚本> SSH_ASKPASS_REQUIRE=force DISPLAY=x ssh ...`；同一错误口令不要连试，避免被锁。原厂与新系统的 root 口令通常不同。
- 刷写、`nvram commit`、`reboot`、格式化 mtd20 都是不可逆或会断网的步骤，每步前向用户确认，并先跑守卫检查。
- 路由器重启期间，经它上网的跳板机也会掉线；用后台轮询等它回来，而不是盲等。
