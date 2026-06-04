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
        """All 18 tools are registered with FastMCP."""
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
        ]

        for tool in expected_tools:
            assert tool in tools, f"Missing tool: {tool}"

        # Verify exact count
        assert len(tools) == 18, f"Expected 18 tools, got {len(tools)}: {tools}"

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
