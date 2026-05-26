# Browser Testing

ADP-OS supports headless browser acceptance tests from the `frontend` runtime.

The frontend runtime is intentionally lightweight by default. It installs Node.js, pnpm, frontend tooling, and browser helper commands, but it does not preinstall browser binaries during bootstrap. Browser engines are large and should be installed on demand inside the VM, not committed to this repository.

## Runtime

Start and sync the frontend runtime:

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 sync start frontend
```

Enter the runtime:

```powershell
ssh adp-os-adp-frontend
cd /home/adp/workspace
```

## Readiness Check

Run:

```bash
adp-frontend-browser-check
```

The check reports:

- Node.js, npm, pnpm, and npx availability.
- Whether Chromium, Chrome, or Firefox are already installed.
- Whether the current workspace has `package.json`.
- Whether `@playwright/test` is installed in the current workspace.

The check command does not download browsers.

## Install Browser Support

Install the default lightweight browser test stack:

```bash
adp-frontend-browser-install chromium
```

Other supported targets:

```bash
adp-frontend-browser-install firefox
adp-frontend-browser-install webkit
adp-frontend-browser-install all
```

The helper installs Playwright Linux dependencies and downloads browser binaries inside the VM. Browser downloads normally live under:

```text
/home/adp/.cache/ms-playwright
```

Do not copy browser caches, downloaded installers, or generated test reports into the ADP-OS repository.

## Project Usage

For a project that already uses Playwright:

```bash
pnpm install
pnpm exec playwright install chromium
pnpm exec playwright test
```

For a project that does not have Playwright yet:

```bash
pnpm add -D @playwright/test
pnpm exec playwright install chromium
pnpm exec playwright test
```

Headless tests are the expected default because ADP runtimes use Ubuntu Server without a desktop session. Headed browser tests require extra display infrastructure such as Xvfb or a desktop/noVNC setup, which is outside the MVP runtime default.

## Sync and Git Hygiene

The frontend sync profile ignores common browser test output:

```text
playwright-report
test-results
blob-report
.playwright
```

The ADP-OS repository also ignores these generated paths. Project repositories may need their own ignore rules for the same artifacts.
