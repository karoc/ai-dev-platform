#!/usr/bin/env python3
"""
Tests for ADP-OS MCP Server.

Verifies:
  - Server module can be imported
  - All tools are registered (18 total)
  - Manifest loading logic
  - Path resolution helpers
  - Output formatting

Does NOT require pwsh.exe or an actual ADP-OS installation.
Run: python tests/test-mcp-server.py
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add project root to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestMCPServer:
    """Test the ADP-OS MCP server module."""

    def test_import(self):
        """Server module imports without errors."""
        import cli.mcp.server as server
        assert server is not None

    def test_all_tools_registered(self):
        """All 26 tools are registered with FastMCP."""
        import cli.mcp.server as server

        # Inspect the mcp instance to find registered tools
        # FastMCP stores tools in _tool_manager._tools
        mcp = server.mcp
        tools = list(mcp._tool_manager._tools.keys())

        expected_tools = [
            "adp_status",
            "adp_doctor",
            "adp_capabilities",
            "adp_workspace_list",
            "adp_workspace_status",
            "adp_workspace_dashboard",
            "adp_workspace_project",
            "adp_workspace_create",
            "adp_workspace_open",
            "adp_workspace_sync",
            "adp_workspace_close",
            "adp_workspace_recipes",
            "adp_workspace_report",
            "adp_up",
            "adp_down",
            "adp_stop",
            "adp_sync_status",
            "adp_sync_stop",
            # In-VM tools (SSH-backed sandbox operations)
            "adp_exec",
            "adp_file_read",
            "adp_file_write",
            "adp_dir_list",
            "adp_glob",
            "adp_grep",
            "adp_file_download",
            "adp_file_upload",
        ]

        for tool in expected_tools:
            assert tool in tools, f"Missing tool: {tool}"

        # Verify exact count
        assert len(tools) == 26, f"Expected 26 tools, got {len(tools)}: {tools}"

    def test_format_output_success(self):
        """_format_output handles successful results."""
        import cli.mcp.server as server

        result = {
            "stdout": "Hello world",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        output = server._format_output(result)
        assert output == "Hello world"

    def test_format_output_with_stderr(self):
        """_format_output includes stderr when present."""
        import cli.mcp.server as server

        result = {
            "stdout": "OK",
            "stderr": "Warning: something",
            "exit_code": 0,
            "success": True,
        }
        output = server._format_output(result)
        assert "OK" in output
        assert "Warning: something" in output
        assert "[stderr]" in output

    def test_format_output_failure(self):
        """_format_output includes exit code for failures."""
        import cli.mcp.server as server

        result = {
            "stdout": "",
            "stderr": "Error occurred",
            "exit_code": 1,
            "success": False,
        }
        output = server._format_output(result)
        assert "Error occurred" in output
        assert "[exit code: 1]" in output

    def test_format_output_empty(self):
        """_format_output handles empty results."""
        import cli.mcp.server as server

        result = {
            "stdout": "",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        output = server._format_output(result)
        assert output == "(no output)"

    def test_format_output_timeout(self):
        """_format_output handles timeout results."""
        import cli.mcp.server as server

        result = {
            "stdout": "",
            "stderr": "Command timed out after 60s",
            "exit_code": -1,
            "success": False,
        }
        output = server._format_output(result)
        assert "timed out" in output
        assert "[exit code: -1]" in output

    # --- Structured output tests ---

    def test_structured_result_success(self):
        """_structured_result wraps raw result with metadata."""
        import cli.mcp.server as server

        result = {
            "stdout": "OK\nAll systems go",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        structured = server._structured_result(result)
        assert structured["_success"] == True
        assert structured["_exit_code"] == 0
        assert "OK" in structured["_text"]
        assert "All systems go" in structured["_text"]

    def test_structured_result_with_parsed(self):
        """_structured_result merges parsed fields."""
        import cli.mcp.server as server

        result = {
            "stdout": "agent running",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        parsed = {"runtimes": [{"name": "agent"}], "runtime_count": 1}
        structured = server._structured_result(result, parsed)
        assert structured["_success"] == True
        assert structured["runtimes"] == [{"name": "agent"}]
        assert structured["runtime_count"] == 1
        # _text still preserved
        assert "agent running" in structured["_text"]

    def test_parse_status(self):
        """_parse_status extracts runtime info from status output."""
        import cli.mcp.server as server

        stdout = """
=== ADP-OS Status ===
agent       running      192.168.242.135  reachable  healthy
frontend    stopped      --               --         --
backend     stopped      --               --         --
"""
        parsed = server._parse_status(stdout)
        assert parsed["runtime_count"] == 3
        assert parsed["running_count"] == 1
        assert parsed["runtimes"][0]["name"] == "agent"
        assert parsed["runtimes"][0]["status"] == "running"
        assert parsed["runtimes"][0]["ip"] == "192.168.242.135"

    def test_parse_doctor(self):
        """_parse_doctor extracts health counts from doctor output."""
        import cli.mcp.server as server

        stdout = """
=== ADP-OS Doctor ===
47 OK
0 issues
5 info
"""
        parsed = server._parse_doctor(stdout)
        assert parsed["ok_count"] == 47
        assert parsed["issue_count"] == 0
        assert parsed["info_count"] == 5
        assert parsed["healthy"] == True

    def test_parse_doctor_with_issues(self):
        """_parse_doctor detects issues."""
        import cli.mcp.server as server

        stdout = """
45 OK
2 issues
! Mutagen not installed
! Sync session halted
3 info
"""
        parsed = server._parse_doctor(stdout)
        assert parsed["ok_count"] == 45
        assert parsed["issue_count"] == 2
        assert parsed["healthy"] == False
        assert len(parsed["issues"]) == 2

    def test_parse_workspace_show(self):
        """_parse_workspace_show extracts project list."""
        import cli.mcp.server as server

        stdout = """
Projects:
  - frontend-app (runtime: frontend)
  - backend-api (runtime: backend)
"""
        parsed = server._parse_workspace_show(stdout)
        assert parsed["project_count"] == 2
        assert parsed["projects"][0]["name"] == "frontend-app"
        assert parsed["projects"][0]["runtime"] == "frontend"

    def test_parse_sync_status(self):
        """_parse_sync_status extracts session states."""
        import cli.mcp.server as server

        stdout = """
agent: healthy
frontend: halted
backend: stale
"""
        parsed = server._parse_sync_status(stdout)
        assert parsed["session_count"] == 3
        assert parsed["healthy_count"] == 1

    def test_parse_capabilities(self):
        """_parse_capabilities extracts capability matrix."""
        import cli.mcp.server as server

        stdout = """
Supported:
  - Windows + VMware
Planned:
  - Hyper-V backend
  - KVM/libvirt
Exploratory:
  - Docker carrier
"""
        parsed = server._parse_capabilities(stdout)
        assert "Windows + VMware" in parsed["supported"]
        assert "Hyper-V backend" in parsed["planned"]
        assert "KVM/libvirt" in parsed["planned"]
        assert "Docker carrier" in parsed["exploratory"]

    def test_all_tools_return_dict(self):
        """All tool return type hints are dict (not str)."""
        import cli.mcp.server as server
        import inspect

        tool_names = [
            "adp_status", "adp_doctor", "adp_capabilities",
            "adp_workspace_list", "adp_workspace_status", "adp_workspace_dashboard",
            "adp_workspace_project", "adp_workspace_create", "adp_workspace_open",
            "adp_workspace_sync", "adp_workspace_close", "adp_workspace_recipes",
            "adp_workspace_report",
            "adp_up", "adp_down", "adp_stop",
            "adp_sync_status", "adp_sync_stop",
            # In-VM tools
            "adp_exec", "adp_file_read", "adp_file_write",
            "adp_dir_list", "adp_glob", "adp_grep",
            "adp_file_download", "adp_file_upload",
        ]

        for name in tool_names:
            func = getattr(server, name)
            sig = inspect.signature(func)
            # Return annotation should be dict
            assert sig.return_annotation == dict, \
                f"{name} returns {sig.return_annotation}, expected dict"

    def test_load_manifest_from_example(self):
        """_load_manifest loads configs/workspace.example.json."""
        import cli.mcp.server as server

        with patch.object(server, '_resolve_adp_home') as mock_home:
            # Point to a temp directory with a sample manifest
            with tempfile.TemporaryDirectory() as tmpdir:
                mock_home.return_value = Path(tmpdir)

                # Create configs/workspace.example.json
                configs_dir = Path(tmpdir) / "configs"
                configs_dir.mkdir()
                manifest = {
                    "version": "1",
                    "projects": [
                        {"name": "test-project", "runtime": "agent", "sync": True}
                    ],
                    "tasks": [],
                }
                with open(configs_dir / "workspace.example.json", "w") as f:
                    json.dump(manifest, f)

                loaded = server._load_manifest()
                assert loaded["version"] == "1"
                assert loaded["projects"][0]["name"] == "test-project"

    def test_find_runtime_for_project(self):
        """_find_runtime_for_project resolves project→runtime."""
        import cli.mcp.server as server

        with patch.object(server, '_load_manifest') as mock_load:
            mock_load.return_value = {
                "projects": [
                    {"name": "frontend-app", "runtime": "frontend"},
                    {"name": "backend-api", "runtime": "backend"},
                    {"name": "agent-scripts", "runtime": "agent"},
                ]
            }

            assert server._find_runtime_for_project("frontend-app") == "frontend"
            assert server._find_runtime_for_project("backend-api") == "backend"
            assert server._find_runtime_for_project("agent-scripts") == "agent"
            assert server._find_runtime_for_project("nonexistent") is None

    def test_find_runtime_no_manifest(self):
        """_find_runtime_for_project returns None when no manifest."""
        import cli.mcp.server as server

        with patch.object(server, '_load_manifest') as mock_load:
            mock_load.return_value = {}
            assert server._find_runtime_for_project("anything") is None

    def test_resolve_adp_home_from_script(self):
        """_resolve_adp_home finds project root relative to script."""
        import cli.mcp.server as server

        # The script is at cli/mcp/server.py, root is ../../ 
        # In the test environment, the actual project root exists
        home = server._resolve_adp_home()
        assert home.exists()
        assert (home / "cli" / "adp.ps1").exists()

    def test_find_pwsh(self):
        """_find_pwsh locates pwsh executable."""
        import cli.mcp.server as server

        # pwsh should be findable in WSL via pwsh.exe or pwsh
        pwsh = server._find_pwsh()
        assert pwsh is not None
        assert "pwsh" in pwsh.lower()

    def test_run_adp_uses_server_wrappers(self):
        """_run_adp preserves server-level helper patch compatibility."""
        import cli.mcp.server as server

        with patch.object(server, '_resolve_adp_home_win') as mock_home_win:
            with patch.object(server, '_find_pwsh') as mock_pwsh:
                with patch.object(server, '_resolve_adp_home') as mock_home:
                    with patch.object(server.subprocess, 'run') as mock_run:
                        mock_home_win.return_value = "D:\\ADP"
                        mock_pwsh.return_value = "pwsh-test"
                        mock_home.return_value = Path("/tmp/adp")
                        mock_run.return_value = MagicMock(
                            stdout="ok\n",
                            stderr="",
                            returncode=0,
                        )

                        result = server._run_adp(["status"], timeout=7)

        cmd = mock_run.call_args.args[0]
        kwargs = mock_run.call_args.kwargs
        assert result["success"] is True
        assert result["stdout"] == "ok"
        assert cmd[:5] == [
            "pwsh-test", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
        ]
        assert cmd[5] == "D:\\ADP\\cli\\adp.ps1"
        assert cmd[6:] == ["status"]
        assert kwargs["timeout"] == 7
        assert kwargs["cwd"] == "/tmp/adp"

    def test_tool_signatures(self):
        """All tool functions have proper signatures and defaults."""
        import cli.mcp.server as server

        # Platform tools
        assert server.adp_status.__name__ == "adp_status"
        assert server.adp_doctor.__name__ == "adp_doctor"
        assert server.adp_capabilities.__name__ == "adp_capabilities"

        # Workspace tools — verify plan_only defaults
        import inspect
        sig_create = inspect.signature(server.adp_workspace_create)
        assert sig_create.parameters["plan_only"].default == True

        sig_close = inspect.signature(server.adp_workspace_close)
        assert sig_close.parameters["plan_only"].default == True

        # Runtime tools — verify plan_only defaults
        sig_up = inspect.signature(server.adp_up)
        assert sig_up.parameters["plan_only"].default == True

        sig_down = inspect.signature(server.adp_down)
        assert sig_down.parameters["plan_only"].default == True

    def test_resolve_adp_home_win_from_env(self):
        """_resolve_adp_home_win reads ADP_HOME_WIN from env."""
        import cli.mcp.server as server

        with patch.dict(os.environ, {"ADP_HOME_WIN": "D:\\Test\\adp-os"}):
            result = server._resolve_adp_home_win()
            assert result == "D:\\Test\\adp-os"

    def test_resolve_adp_home_win_windows_native(self):
        """_resolve_adp_home_win returns adp_home directly on Windows (no wslpath)."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            with patch.object(server, '_resolve_adp_home') as mock_home:
                mock_home.return_value = Path("D:/Dev/ai-dev-platform")
                # ADP_HOME_WIN is NOT set — should return ADP_HOME directly
                with patch.dict(os.environ, {}, clear=True):
                    result = server._resolve_adp_home_win()
                    assert result == str(Path("D:/Dev/ai-dev-platform"))

    def test_resolve_adp_home_windows_fallback(self):
        """_resolve_adp_home searches Windows-native paths when IS_WINDOWS."""
        import cli.mcp.server as server

        # On Windows, it should not try WSL mount paths
        with patch.object(server, 'IS_WINDOWS', True):
            # Step 2 (relative to script) should still work
            # The actual file exists, so it should find it
            home = server._resolve_adp_home()
            assert home.exists()
            assert (home / "cli" / "adp.ps1").exists()

    # --- Path normalization tests ---

    def test_normalize_windows_empty(self):
        """_normalize_windows_path returns empty string for falsy input."""
        import cli.mcp.server as server

        assert server._normalize_windows_path("") == ""
        assert server._normalize_windows_path(None) is None

    def test_normalize_windows_slash_style(self):
        """_normalize_windows_path handles both forward and backward slashes."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            # Backslashes normalized to forward slashes
            result = server._normalize_windows_path("D:\\Dev\\ai-dev-platform")
            assert "\\" not in result
            assert "D:/Dev/ai-dev-platform" == result

            # Forward slashes pass through
            result = server._normalize_windows_path("D:/Dev/ai-dev-platform")
            assert "D:/Dev/ai-dev-platform" == result

    def test_normalize_windows_on_windows(self):
        """_normalize_windows_path returns path as-is on native Windows."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            result = server._normalize_windows_path("C:\\Users\\test\\file.iso")
            assert result == "C:/Users/test/file.iso"

            result = server._normalize_windows_path("D:/ISOs/ubuntu.iso")
            assert result == "D:/ISOs/ubuntu.iso"

    def test_normalize_windows_wsl_mount_path(self):
        """_normalize_windows_path converts /mnt/X/... to X:\\... on WSL."""
        import cli.mcp.server as server

        # On WSL (IS_WINDOWS=False), /mnt/d/... should be converted
        with patch.object(server, 'IS_WINDOWS', False):
            # Mock subprocess.run to return a Windows path
            with patch.object(server.subprocess, 'run') as mock_run:
                mock_run.return_value = MagicMock(returncode=0, stdout="D:\\ISOs\\ubuntu.iso\n")

                result = server._normalize_windows_path("/mnt/d/ISOs/ubuntu.iso")
                assert result == "D:\\ISOs\\ubuntu.iso"

    def test_normalize_windows_non_mount_path(self):
        """_normalize_windows_path keeps non-mount paths unchanged on WSL."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', False):
            # A regular path like /home/user/file.iso stays as-is
            result = server._normalize_windows_path("/home/user/file.iso")
            assert result == "/home/user/file.iso"

    def test_normalize_windows_must_exist(self):
        """_normalize_windows_path validates existence when must_exist=True."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            # A nonexistent path should raise FileNotFoundError
            with patch.object(server.Path, 'exists', return_value=False):
                try:
                    server._normalize_windows_path("Z:\\nonexistent\\file.iso", must_exist=True)
                    assert False, "Should have raised FileNotFoundError"
                except FileNotFoundError:
                    pass

    def test_wsl_to_win_conversion(self):
        """_wsl_to_win converts WSL path to Windows path via wslpath."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', False):
            with patch.object(server.subprocess, 'run') as mock_run:
                mock_run.return_value = MagicMock(returncode=0, stdout="D:\\Dev\\project\n")

                result = server._wsl_to_win("/mnt/d/Dev/project")
                assert result == "D:\\Dev\\project"

    def test_wsl_to_win_native_windows(self):
        """_wsl_to_win returns path as-is on native Windows."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            result = server._wsl_to_win("D:\\Dev\\project")
            assert result == "D:/Dev/project"

    def test_win_to_wsl_conversion(self):
        """_win_to_wsl converts Windows path to WSL path via wslpath."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', False):
            with patch.object(server.subprocess, 'run') as mock_run:
                mock_run.return_value = MagicMock(returncode=0, stdout="/mnt/d/Dev/project\n")

                result = server._win_to_wsl("D:\\Dev\\project")
                assert result == "/mnt/d/Dev/project"

    def test_win_to_wsl_native_windows(self):
        """_win_to_wsl returns path as-is on native Windows."""
        import cli.mcp.server as server

        with patch.object(server, 'IS_WINDOWS', True):
            result = server._win_to_wsl("D:\\Dev\\project")
            assert result == "D:/Dev/project"
def run_tests():
    """Run all tests and report results."""
    test = TestMCPServer()
    passed = 0
    failed = 0

    test_methods = [
        m for m in dir(test)
        if m.startswith("test_") and callable(getattr(test, m))
    ]

    for method_name in test_methods:
        method = getattr(test, method_name)
        try:
            method()
            print(f"  ✓ {method_name}")
            passed += 1
        except Exception as e:
            print(f"  ✗ {method_name}: {e}")
            failed += 1

    print(f"\n{passed} passed, {failed} failed, {len(test_methods)} total")
    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
