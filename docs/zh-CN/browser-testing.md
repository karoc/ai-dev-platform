# 浏览器测试

简体中文 | [English](../browser-testing.md)

ADP-OS 支持从 `frontend` 运行时执行 headless 浏览器验收测试。

Frontend 运行时默认保持轻量。它会安装 Node.js、pnpm、前端工具链和浏览器辅助命令，但不会在 bootstrap 期间预装浏览器二进制。浏览器引擎体积较大，应按需安装到 VM 内，而不是提交到本仓库。

## 运行时

启动并同步 frontend 运行时：

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 sync start frontend
```

进入运行时：

```powershell
ssh adp-os-adp-frontend
cd /home/adp/workspace
```

## 就绪检查

运行：

```bash
adp-frontend-browser-check
```

该检查会报告：

- Node.js、npm、pnpm 和 npx 是否可用。
- Chromium、Chrome 或 Firefox 是否已经安装。
- 当前工作区是否存在 `package.json`。
- 当前工作区是否安装了 `@playwright/test`。

检查命令不会下载浏览器。

## 安装浏览器支持

安装默认的轻量浏览器测试栈：

```bash
adp-frontend-browser-install chromium
```

其他支持目标：

```bash
adp-frontend-browser-install firefox
adp-frontend-browser-install webkit
adp-frontend-browser-install all
```

该辅助命令会安装 Playwright Linux 依赖，并在 VM 内下载浏览器二进制。浏览器下载通常位于：

```text
/home/adp/.cache/ms-playwright
```

不要把浏览器缓存、下载的安装器或生成的测试报告复制到 ADP-OS 仓库。

## 项目使用

对于已经使用 Playwright 的项目：

```bash
pnpm install
pnpm exec playwright install chromium
pnpm exec playwright test
```

对于还没有 Playwright 的项目：

```bash
pnpm add -D @playwright/test
pnpm exec playwright install chromium
pnpm exec playwright test
```

Headless 测试是默认预期，因为 ADP 运行时使用没有桌面会话的 Ubuntu Server。Headed 浏览器测试需要额外显示基础设施，例如 Xvfb 或 desktop/noVNC，这不属于 MVP 默认运行时能力。

## 同步和 Git 卫生

Frontend 同步 profile 会忽略常见浏览器测试输出：

```text
playwright-report
test-results
blob-report
.playwright
```

ADP-OS 仓库也会忽略这些生成路径。项目仓库自身可能也需要配置同样的 ignore 规则。
