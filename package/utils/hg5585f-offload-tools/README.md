# HG5585F 开机自检和日志采集

可选包 `hg5585f-offload-tools` 提供开机服务和命令
`hg5585f-offload-check`，用于当前 WED TX、NPU RX/重排序及 Linux 转发模式。
需要本仓库 mt76 补丁 131 提供的 `offload_status`；不需要启用 `npu_probe` 参数。

工具只读取状态，并在 `/tmp` 创建报告。它不会启用加速、挂载 debugfs、写寄存器、
清空计数或日志、修改网络配置、产生测试流量或触发驱动恢复。

## 手动检查

```sh
hg5585f-offload-check --expect combined
```

选择当前应运行的模式：`native`、`rx`、`wed`、`combined`。
默认 `auto` 根据设备树和驱动请求状态判断。明确指定 `--expect` 可发现启动了错误的 FIT 配置。

默认间隔 3 秒采集两次，输出文本、JSON 和权限受限的 `.tar.gz` 日志包。
命令会打印准确路径，例如 `/tmp/hg5585f-offload.ABC123.tar.gz`。
使用 `--output /tmp/my-offload-report` 可指定一个尚不存在的报告目录；不会覆盖已有目录。

在已有用户流量时，可要求观察到两个方向的推进：

```sh
hg5585f-offload-check --expect combined --require-traffic --interval 5 --samples 3
```

命令本身不会发包。无流量不等于硬件故障。

| 结果 | 含义 | 退出码 |
| --- | --- | --- |
| `PASS` | 请求的路径已就绪，且采样中都观察到对应计数推进 | 0 |
| `READY` | 路径已就绪，但没有观察到全部所需方向的流量 | 0 |
| `SKIP` | 匹配的驱动明确报告原生模式，没有请求加速 | 0 |
| `WARN` | 数据缺失、读取超时、恢复跨过采样窗口、计数不可读或日志中有异常证据 | 2 |
| `FAIL` | 请求的后端未挂接、选错模式、WED 参数关闭、队列停止或 DMA 已被隔离 | 1 |

参数错误退出 64，报告写入失败退出 73。报告完成时存在 `complete` 文件，
文本报告为 `report.txt`，机器可读结果为 `summary.json`。

## 开机检查

安装可选包后，`/etc/init.d/hg5585f-offload-check` 在启动阶段执行一次检查，
最多等待驱动 60 秒，再采两次快照。不设置 respawn，不循环重启驱动或服务。
报告路径和结论写入系统服务日志；数据保存在 `/tmp`，重启后不保留。

配置文件 `/etc/config/hg5585f-offload-check`：

```text
config check 'main'
        option enabled '1'
        option expect 'auto'
        option wait '60'
        option interval '3'
        option samples '2'
        option require_traffic '0'
```

`enabled=0` 可关闭检查。也可以手动执行
`/etc/init.d/hg5585f-offload-check restart` 重新采集。

## 采集和判定范围

- 状态：请求的模式、后端挂接、接收队列、停止/隔离标志和恢复状态。
- NPU：返回 Linux 的完整帧数及主机交付丢弃计数。计数按 NAPI 批次更新。
- WED：使用已核对的两个 TX MIB；在停机、恢复、隔离或 read-clear 模式下不读取 MIB。
- 恢复：通过驱动实例标识及 WM/WA 重置次数识别重新加载和恢复；跨越恢复时省略流量差值。
- 原始证据：每次的内核日志尾部、CPU、IRQ、内存、模块、网络设备计数，以及系统版本和设备树模式。

每次读取有超时限制，每个原始文件最多约 128 KiB。缺少 `timeout`、debugfs 未挂载或
运行旧驱动时会保留可用信息并报告观测不足，不会自动调整系统。
包会选择 MT7915 驱动和 mac80211 debugfs 支持；仍需要使用匹配的驱动构建。

两个 PHY 可能显示同一个控制器的计数，通过 `instance` 识别；不能把它们相加。
32 位计数按相邻快照计算回绕差值。NPU 主机交付计数与 WED MIB 的计量单位不同，
它们只证明对应通道有推进，不证明无线 ACK、端到端吞吐或完整 RX→PPE 转发已经正确。
工具能观察恢复及恢复后的状态，不会主动进行重置试验。

## 单独复制或离线分析

可把 `files/hg5585f-offload-check` 与 `files/offload-report.awk`
放在设备同一个目录，用 `sh ./hg5585f-offload-check` 运行。
脚本优先使用同目录的 AWK 文件。支持 BusyBox ash/awk，不依赖 Python、jq 或完整 GNU 工具集。

开发验证可用 `--root DIRECTORY` 指向包含 `proc/`、`sys/` 和可选 `dmesg.txt` 的离线目录。
此时不会读取运行脚本所在主机的内核日志。目录中的输入保持只读；报告另建目录。
路径支持空格，不支持换行。
