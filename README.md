# Redmi AX3000 (RA81) · ImmortalWrt + OpenClash 精简固件

> ## ⚠️ 声明：仅供学习与研究用途
>
> - 本仓库记录的是一次个人刷机实践，用于学习 OpenWrt 固件结构、UBI/NAND 分区和小闪存设备的空间优化。
> - **刷机可能导致设备变砖、失去保修**，所有操作风险由使用者自行承担，作者不对任何损失负责。
> - 请遵守你所在地的法律法规，不得将本项目用于任何违法用途。
> - 固件基于第三方社区移植（非 OpenWrt / ImmortalWrt 官方支持机型），未经过充分测试。

Redmi AX3000（硬件代号 RA81，高通 IPQ5000，128MB NAND）每个系统分区只有 36MiB，
OpenClash 插件 + mihomo 内核按常规方式“刷完再装”放不下。本项目的做法：

1. 基于 [kmiit/Redmi_AX3000_immortalwrt](https://github.com/kmiit/Redmi_AX3000_immortalwrt) 的 ImmortalWrt 24.10 镜像，
   直接往 rootfs 里注入 OpenClash（去掉两个 Web 面板和 GeoSite.dat）及其依赖，内核卷与原版逐字节一致。
2. mihomo 内核放不进系统分区（精简后 xz 仍有 11.4MB），改放到 OpenWrt 用不上的 **mtd20 `overlay` 分区**，
   格式化为 UBIFS 卷 `ocdata`，开机由 `/etc/init.d/ocdata` 挂到 `/etc/openclash`。
3. 只写空闲启动槽，**原厂系统完整保留在另一个槽**，一条命令即可切回。

## 下载

见 [Releases](../../releases)：

| 文件 | 说明 |
|---|---|
| `ra81-immortalwrt-openclash-generic-factory.ubi` | 通用版固件（无任何预置账号/密码），用 `ubiformat` 写入空闲 rootfs 槽 |
| `clash_meta.gz` | mihomo v1.19.32 linux/arm64，去 gVisor + strip，gzip 压缩（镜像无 xz 解压） |
| `SHA256SUMS` | 校验值 |

```
cad6e112723e03228139ffe0f56a4e44b4543d6406963bbbb67edc77fbc292bc  ra81-immortalwrt-openclash-generic-factory.ubi
5719440fcd0f3f7b2f522a7eea42a5ca013c3bde2f67e72b47ca81ecb0d295e1  clash_meta.gz
f4408c7a2d51578479ce8706b6b3dfa3dad542bd6fa415d77b157c51c4f7d462  clash_meta (解压后)
```

### 通用版刷完后的默认状态

- LAN `192.168.1.1`，**root 无密码**，请立即设置。
- WiFi 由系统自动生成，SSID 为 `ImmortalWrt`，可能**未加密**——务必用网线首次登录并立刻改 WiFi 密码。
- WAN 默认 DHCP；PPPoE 拨号需在 LuCI 里自行配置。
- OpenClash 已装好但未启用，内核需按下文初始化 mtd20 后才可用。

## 固件内容

| 组件 | 版本 / 说明 |
|---|---|
| 系统 | ImmortalWrt 24.10-SNAPSHOT r0-cb4f52a（kmiit 构建），Linux 6.6.137，aarch64_cortex-a53 |
| luci-app-openclash | 0.47.156，移除 metacubexd、zashboard 面板与 GeoSite.dat |
| 依赖 | ruby 3.3 + yaml/psych 等、curl、ip-full、bash、unzip、kmod-tun、kmod-nft-tproxy、kmod-inet-diag（版本见 `build/offline-packages.manifest.json`） |
| ocdata | 开机脚本：只挂载 mtd20 上已存在的 `ocdata` 卷，**从不自动格式化** |

空间：kernel 43 LEB + rootfs 124 LEB，刷后 `rootfs_data` 约 11.7MiB 可写。

## 刷机流程（概要）

完整步骤、守卫检查与排错见 [skills/ra81-immortalwrt-openclash/SKILL.md](skills/ra81-immortalwrt-openclash/SKILL.md)。

1. **前提**：原厂 SSH 已解锁（社区工具 [XMiR-Patcher](https://github.com/openwrt-xiaomi/xmir-patcher)）；**备份全部 mtd 分区**（尤其 ART/bdata）；准备好原厂恢复固件和 MIWIFIRepairTool；人在现场、备网线。
2. 确认当前运行槽：`cat /proc/cmdline`（`ubi.mtd=rootfs_1` 即运行在 mtd19）。
3. 写入空闲槽并切换：
   ```sh
   ubiformat /dev/mtd18 -y -f /tmp/ra81-immortalwrt-openclash-generic-factory.ubi
   nvram set flag_boot_rootfs=0; nvram set flag_last_success=0
   nvram set flag_try_sys1_failed=0; nvram set flag_try_sys2_failed=0
   nvram commit; reboot
   ```
4. 新系统里确认 `fw_printenv flag_boot_rootfs` 能读到 `0`（回退通道可用）。
5. 初始化 mtd20 并放入内核：`sh router/init-mtd20-ocdata.sh`（需先把 `clash_meta.gz` 传到 `/tmp`），重启。
6. 在 LuCI 或用 uci 添加订阅、启用 OpenClash。**国内使用需关闭 dns.google / cloudflare DoH fallback**，否则节点解析失败（详见 SKILL.md）。

**回退**：新系统里 `fw_setenv flag_boot_rootfs 1; reboot` 回原厂；进不去则用 MIWIFIRepairTool TFTP 刷回原厂。

## 自己构建

在 Debian 容器中依次执行：

```sh
bash build/01-setup.sh        # 装工具、解开 ImageBuilder 与 kmiit factory.ubi
bash build/02-fetch-deps.sh   # 下载离线依赖并按 manifest 校验 sha256
bash build/03-build-mihomo.sh # 编译精简 mihomo
bash build/04-pack-image.sh   # 注入 OpenClash + 依赖，重新 ubinize
```

构建输入（放到 `/in`）：kmiit release
[`ci-redmi_ax3000-24.10-20260514-122123-UTC`](https://github.com/kmiit/Redmi_AX3000_immortalwrt/releases/tag/ci-redmi_ax3000-24.10-20260514-122123-UTC)
中的 `immortalwrt-imagebuilder-qualcommax-ipq50xx.Linux-x86_64.tar.zst` 与 `...-redmi_ax3000-squashfs-factory.ubi`，
以及 [OpenClash](https://github.com/vernesong/OpenClash/releases) 的 `luci-app-openclash_0.47.156_all.ipk`。

私有构建可用 `CUSTOM_UCI_DEFAULTS`（参考 `examples/99-zzz-custom-net.example`）预置 LAN/PPPoE/WiFi，刷完网络自动恢复；
**这样构建的镜像包含你的密码，切勿公开发布。**

## 仓库结构

```
build/                      构建脚本与依赖清单
files/etc/init.d/ocdata     开机挂载 mtd20 ocdata 卷
router/init-mtd20-ocdata.sh 在路由器上初始化 mtd20 并安装内核
examples/                   私有构建用的首启配置模板（占位符）
skills/                     Claude Code skill：完整流程、守卫检查、踩坑记录
```

## 致谢与许可

- [kmiit/Redmi_AX3000_immortalwrt](https://github.com/kmiit/Redmi_AX3000_immortalwrt)、[ImmortalWrt](https://github.com/immortalwrt/immortalwrt)、[hzyitc/openwrt-redmi-ax3000](https://github.com/hzyitc/openwrt-redmi-ax3000)
- [vernesong/OpenClash](https://github.com/vernesong/OpenClash)、[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（源码 tag `v1.19.32`，构建命令见 `build/03-build-mihomo.sh`）
- [openwrt-xiaomi/xmir-patcher](https://github.com/openwrt-xiaomi/xmir-patcher)

本仓库脚本以 [GPL-3.0](LICENSE) 发布。固件中各组件遵循其各自上游许可证，对应源码见上方链接。
本项目与小米、Redmi、OpenWrt、ImmortalWrt 官方无关。
