# ADP-OS 10 分钟生存价值演示

> 参见[英文版](../demo-script.md)获取完整的演示脚本、前置准备清单和故障排除指南。
>
> See the [English version](../demo-script.md) for the full presenter script, pre-demo checklist, and troubleshooting guide.

## 录制前公开核对

公开录制或现场演示必须能够只依赖公开仓库复现：

- 先运行 `adpos demo -Plan` 查看 providerless 就绪引导。它只是引导信息：不会运行 demo、创建或启动 VM、修改 sync session、创建 snapshot、打开 SSH、修改主机配置、修改 PATH、写入文件、发布录制或批准外联。
- 只使用公开 ADP-OS checkout、公开文档、公开 recipe manifest、公开 issue templates，以及公开 ADP-OS 命令生成的 artifacts。
- 面向用户的 shell 命令是 `adpos`；仓库根目录中的 `.\adpos.cmd` 只是 `PATH` 刷新前的本地 wrapper。不要引入 `adp` shell 命令。
- 不要依赖私有维护者脚本、私有清理笔记、私有仓库、私有反馈记录、未发布支持渠道或未文档化的 VMware 介入。
- 录制前必须确认 VMware 可达，`agent` 已预置，并且 `adpos doctor`、`adpos status agent`、`adpos sync status` 都显示公开就绪状态。
- 在 VM mutation 前停止 `agent` sync，restore 期间保持停止，只能在选择 host 或 VM workspace 作为 source of truth 后再重启 sync。
- evidence ZIP 必须包含 `README.txt`、`snapshot-hashes.json`、`operation-log.json`、`workspace-report.md` 和 `adp-workspace.json`。
- 如果 restore readiness 不能通过公开 ADP 命令展示、需要未文档化 host-key 修复、需要私有清理，或画面中出现 credentials、私有本机路径、私有维护者上下文、私有反馈记录或无关通知，停止录制并把这次运行归为彩排或产品就绪 evidence。
- 录制准备不包含外联。maintainer 明确启用或批准前，不要公开发布、自动外联、爬取、群发、收集 testimonial、排队联系人、联系目标用户，也不要把 Discord 或 GitHub Discussions 当成已批准或官方渠道。
