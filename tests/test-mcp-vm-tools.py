#!/usr/bin/env python3
"""
Tests for ADP-OS MCP server in-VM helpers and tools.

Does NOT require running VMs or VMware.
Run: python tests/test-mcp-vm-tools.py
"""

import sys
from pathlib import Path
from unittest.mock import patch

# Add project root to path for imports
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestMCPVMTools:
    """Test ADP-OS MCP in-VM helper and tool behavior."""

    # --- Sanitize path tests ---

    def test_sanitize_path_normal(self):
        """_sanitize_path accepts normal absolute paths."""
        import cli.mcp.server as server

        assert server._sanitize_path("/home/adp/workspace") == "/home/adp/workspace"
        assert server._sanitize_path("/tmp/test.py") == "/tmp/test.py"

    def test_sanitize_path_empty(self):
        """_sanitize_path rejects empty paths."""
        import cli.mcp.server as server

        try:
            server._sanitize_path("")
            assert False, "Should have raised ValueError"
        except ValueError as e:
            assert "must not be empty" in str(e)

    def test_sanitize_path_null_byte(self):
        """_sanitize_path rejects paths with null bytes."""
        import cli.mcp.server as server

        try:
            server._sanitize_path("/tmp/test\x00hidden")
            assert False, "Should have raised ValueError"
        except ValueError as e:
            assert "null byte" in str(e)

    def test_sanitize_path_traversal(self):
        """_sanitize_path rejects path traversal attempts."""
        import cli.mcp.server as server

        for bad_path in ["../etc/passwd", "/home/../etc/shadow", "./..", "foo/../../bar"]:
            try:
                server._sanitize_path(bad_path)
                assert False, f"Should have raised ValueError for {bad_path}"
            except ValueError as e:
                assert ".." in str(e)

    # --- SSH result tests ---

    def test_ssh_result_success(self):
        """_ssh_result wraps SSH results with runtime."""
        import cli.mcp.server as server

        result = {
            "stdout": "hello",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        out = server._ssh_result("agent", result)
        assert out["_success"] == True
        assert out["runtime"] == "agent"
        assert "hello" in out["_text"]

    def test_ssh_result_with_parsed(self):
        """_ssh_result merges parsed fields."""
        import cli.mcp.server as server

        result = {
            "stdout": "line1\nline2",
            "stderr": "",
            "exit_code": 0,
            "success": True,
        }
        out = server._ssh_result("agent", result, {"entries": ["line1", "line2"]})
        assert out["entries"] == ["line1", "line2"]
        assert out["runtime"] == "agent"

    # --- In-VM tool signature tests ---

    def test_vm_tool_signatures(self):
        """All in-VM tools have proper signatures with correct defaults."""
        import cli.mcp.server as server
        import inspect

        # adp_exec
        sig = inspect.signature(server.adp_exec)
        assert sig.parameters["runtime"].default is inspect.Parameter.empty
        assert sig.parameters["command"].default is inspect.Parameter.empty
        assert sig.parameters["timeout"].default == 120

        # adp_file_read
        sig = inspect.signature(server.adp_file_read)
        assert sig.parameters["runtime"].default is inspect.Parameter.empty
        assert sig.parameters["path"].default is inspect.Parameter.empty

        # adp_file_write
        sig = inspect.signature(server.adp_file_write)
        assert sig.parameters["plan_only"].default == True
        assert sig.parameters["append"].default == False

        # adp_dir_list
        sig = inspect.signature(server.adp_dir_list)
        assert sig.parameters["max_depth"].default == 2

        # adp_glob
        sig = inspect.signature(server.adp_glob)
        assert sig.parameters["max_results"].default == 200
        assert sig.parameters["include_dirs"].default == False

        # adp_grep
        sig = inspect.signature(server.adp_grep)
        assert sig.parameters["max_results"].default == 100
        assert sig.parameters["literal"].default == False
        assert sig.parameters["case_sensitive"].default == False

        # adp_file_download
        sig = inspect.signature(server.adp_file_download)
        assert "runtime" in sig.parameters
        assert "path" in sig.parameters

        # adp_file_upload
        sig = inspect.signature(server.adp_file_upload)
        assert sig.parameters["plan_only"].default == True

    # --- adp_file_write plan_only tests ---

    def test_file_write_plan_only(self):
        """adp_file_write plan_only returns preview without executing."""
        import cli.mcp.server as server

        with patch.object(server, '_sanitize_path', return_value="/tmp/test.py"):
            result = server.adp_file_write(
                runtime="agent",
                path="/tmp/test.py",
                content="hello world",
                plan_only=True,
            )
            assert result["plan_only"] == True
            assert result["bytes_planned"] == 11
            assert "[plan]" in result["_text"]
            assert result["_success"] == True

    # --- adp_file_upload tests ---

    def test_file_upload_invalid_base64(self):
        """adp_file_upload rejects invalid base64 content."""
        import cli.mcp.server as server

        result = server.adp_file_upload(
            runtime="agent",
            path="/tmp/test.bin",
            content_base64="not-valid-base64!!!",
            plan_only=False,
        )
        assert result["_success"] == False
        assert "Invalid base64" in result["_text"]

    def test_file_upload_plan_only(self):
        """adp_file_upload plan_only returns preview."""
        import cli.mcp.server as server
        import base64

        content_b64 = base64.b64encode(b"binary data").decode("ascii")
        with patch.object(server, '_sanitize_path', return_value="/tmp/test.bin"):
            result = server.adp_file_upload(
                runtime="agent",
                path="/tmp/test.bin",
                content_base64=content_b64,
                plan_only=True,
            )
            assert result["plan_only"] == True
            assert result["bytes_planned"] == 11
            assert "[plan]" in result["_text"]


def run_tests():
    """Run all tests and report results."""
    test = TestMCPVMTools()
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
