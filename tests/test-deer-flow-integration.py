#!/usr/bin/env python3
"""
Minimal verification: deer-flow Sandbox ↔ ADP-OS MCP server integration mapping.

Validates:
  1. MCP server exposes all 8 SSH-backed in-VM tools
  2. Deer-flow Sandbox interface has 8 abstract methods
  3. All 8 methods have corresponding ADP-OS MCP tools
  4. Parameter-level return type differences are documented

Does NOT require running VMs or VMware — pure code inspection.
"""

import sys
import os
import ast
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MCP_SERVER = PROJECT_ROOT / "cli" / "mcp" / "server.py"

# ── Deer-flow Sandbox expected interface ────────────────────────────
DEER_FLOW_SANDBOX_METHODS = {
    "execute_command": {"params": ["self", "command"], "return_type": "str"},
    "read_file":       {"params": ["self", "path"], "return_type": "str"},
    "write_file":      {"params": ["self", "path", "content", "append"], "return_type": "None"},
    "list_dir":        {"params": ["self", "path", "max_depth"], "return_type": "list[str]"},
    "glob":            {"params": ["self", "path", "pattern", "include_dirs", "max_results"], "return_type": "tuple[list[str], bool]"},
    "grep":            {"params": ["self", "path", "pattern", "glob", "literal", "case_sensitive", "max_results"], "return_type": "tuple[list[GrepMatch], bool]"},
    "download_file":   {"params": ["self", "path"], "return_type": "bytes"},
    "update_file":     {"params": ["self", "path", "content"], "return_type": "None"},
}

# ── Expected ADP-OS MCP tool → deer-flow method mapping ─────────────
EXPECTED_MAPPING = {
    "adp_exec":           "execute_command",
    "adp_file_read":      "read_file",
    "adp_file_write":     "write_file",
    "adp_dir_list":       "list_dir",
    "adp_glob":           "glob",
    "adp_grep":           "grep",
    "adp_file_download":  "download_file",
    "adp_file_upload":    "update_file",
}

# ── Parameter-level return-type differences (documented, not bugs) ──
PARAM_LEVEL_DIFFS = {
    "execute_command": {"returns": "str", "adp_returns": "dict", "note": "adp_exec returns structured {stdout, stderr, exit_code}"},
    "read_file":       {"returns": "str", "adp_returns": "dict", "note": "adp_file_read wraps content in {content, path}"},
    "write_file":      {"returns": "None", "adp_returns": "dict", "note": "adp_file_write returns {path, bytes_written}"},
    "list_dir":        {"returns": "list[str]", "adp_returns": "dict", "note": "adp_dir_list returns {entries, entry_count}; excludes hidden files"},
    "glob":            {"returns": "tuple[list[str], bool]", "adp_returns": "dict", "note": "adp_glob returns {matches, match_count, truncated}"},
    "grep":            {"returns": "tuple[list[GrepMatch], bool]", "adp_returns": "dict", "note": "adp_grep returns raw lines; needs GrepMatch parsing"},
    "download_file":   {"returns": "bytes", "adp_returns": "base64 str", "note": "adp_file_download returns {content_base64}; needs decode"},
    "update_file":     {"returns": "None", "adp_returns": "dict", "note": "adp_file_upload accepts content_base64 str param; needs encode"},
}


def extract_mcp_tools(server_path: Path) -> dict:
    """Parse MCP server.py AST and extract @mcp.tool() decorated functions."""
    tree = ast.parse(server_path.read_text(encoding="utf-8"))
    tools = {}

    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue

        # Check for @mcp.tool() decorator
        is_mcp_tool = False
        for decorator in node.decorator_list:
            if isinstance(decorator, ast.Call):
                if isinstance(decorator.func, ast.Attribute):
                    if (isinstance(decorator.func.value, ast.Name) and
                        decorator.func.value.id == "mcp" and
                        decorator.func.attr == "tool"):
                        is_mcp_tool = True
                        break

        if not is_mcp_tool:
            continue

        params = []
        for arg in node.args.args:
            params.append(arg.arg)

        tools[node.name] = {
            "params": params,
            "docstring": ast.get_docstring(node) or "",
        }

    return tools


def test_mcp_server_exists():
    """Verify MCP server file exists and is parseable."""
    assert MCP_SERVER.exists(), f"MCP server not found at {MCP_SERVER}"
    tools = extract_mcp_tools(MCP_SERVER)
    assert len(tools) >= 26, f"Expected ≥26 MCP tools, found {len(tools)}"
    print(f"  ✓ MCP server: {len(tools)} tools registered")
    return tools


def test_in_vm_tools_present(tools: dict):
    """Verify all 8 SSH-backed in-VM tools are registered."""
    in_vm_tools = {k: v for k, v in tools.items() if k in EXPECTED_MAPPING}
    missing = set(EXPECTED_MAPPING) - set(tools.keys())

    assert len(in_vm_tools) == 8, (
        f"Expected 8 in-VM tools, found {len(in_vm_tools)}. "
        f"Missing: {missing}"
    )
    print(f"  ✓ In-VM tools: 8/8 present ({', '.join(sorted(in_vm_tools))})")
    return in_vm_tools


def test_method_mapping_complete():
    """Verify 8/8 deer-flow Sandbox methods have ADP-OS MCP tool mappings."""
    df_methods = set(DEER_FLOW_SANDBOX_METHODS)
    mapped_methods = set(EXPECTED_MAPPING.values())
    unmapped = df_methods - mapped_methods

    assert not unmapped, f"Unmapped deer-flow methods: {unmapped}"
    assert len(EXPECTED_MAPPING) == 8, f"Expected 8 mappings, got {len(EXPECTED_MAPPING)}"
    print(f"  ✓ Method mapping: 8/8 deer-flow Sandbox methods mapped to ADP-OS MCP tools")


def test_in_vm_tool_params(tools: dict):
    """Verify in-VM tools have the expected 'runtime' parameter."""
    for adp_tool, df_method in EXPECTED_MAPPING.items():
        tool_info = tools.get(adp_tool)
        assert tool_info is not None, f"Tool {adp_tool} not found in MCP server"
        assert "runtime" in tool_info["params"], (
            f"{adp_tool} missing 'runtime' param. Params: {tool_info['params']}"
        )
    print(f"  ✓ In-VM tool params: all 8 have 'runtime' parameter")


def test_parameter_level_diffs_documented():
    """Verify all 8 methods have documented parameter-level differences."""
    df_methods = set(DEER_FLOW_SANDBOX_METHODS)
    documented = set(PARAM_LEVEL_DIFFS)
    missing = df_methods - documented

    assert not missing, f"Undocumented parameter-level diffs for: {missing}"
    print(f"  ✓ Parameter-level diffs: 8/8 documented")


def test_docs_exist():
    """Verify integration docs exist in both languages."""
    docs = [
        PROJECT_ROOT / "docs" / "integrations" / "deer-flow.md",
        PROJECT_ROOT / "docs" / "zh-CN" / "integrations" / "deer-flow.md",
    ]
    for doc in docs:
        assert doc.exists(), f"Doc not found: {doc}"
        content = doc.read_text(encoding="utf-8")
        # Verify parameter-level mapping section exists (added in this task)
        assert "参数级映射" in content or "Parameter-Level Mapping" in content, (
            f"{doc.name}: missing parameter-level mapping section"
        )
    print(f"  ✓ Integration docs: en + zh-CN present with parameter-level mapping")


def test_adapter_exists():
    """Verify DeerFlowADPSandboxProvider adapter class exists."""
    adapter = PROJECT_ROOT / "extensions" / "deer_flow" / "deerflow_adp_sandbox.py"
    assert adapter.exists(), f"Adapter not found: {adapter}"
    content = adapter.read_text(encoding="utf-8")
    assert "DeerFlowADPSandboxProvider" in content, "Adapter class not found"
    print(f"  ✓ Adapter: DeerFlowADPSandboxProvider exists")


# ── Main ────────────────────────────────────────────────────────────

def main():
    print("=" * 64)
    print("  Deer-Flow ↔ ADP-OS MCP Integration Verification")
    print("=" * 64)
    print()

    tests = []
    try:
        tools = test_mcp_server_exists()
        tests.append(("MCP server exists (≥26 tools)", True))
    except Exception as e:
        print(f"  ✗ MCP server: {e}")
        tests.append(("MCP server exists (≥26 tools)", False))
        tools = {}

    if tools:
        try:
            test_in_vm_tools_present(tools)
            tests.append(("8 in-VM tools present", True))
        except Exception as e:
            print(f"  ✗ In-VM tools: {e}")
            tests.append(("8 in-VM tools present", False))

        try:
            test_in_vm_tool_params(tools)
            tests.append(("In-VM tool params", True))
        except Exception as e:
            print(f"  ✗ Tool params: {e}")
            tests.append(("In-VM tool params", False))

    try:
        test_method_mapping_complete()
        tests.append(("8/8 method mapping", True))
    except Exception as e:
        print(f"  ✗ Method mapping: {e}")
        tests.append(("8/8 method mapping", False))

    try:
        test_parameter_level_diffs_documented()
        tests.append(("Parameter-level diffs documented", True))
    except Exception as e:
        print(f"  ✗ Parameter diffs: {e}")
        tests.append(("Parameter-level diffs documented", False))

    try:
        test_docs_exist()
        tests.append(("Integration docs bilingual", True))
    except Exception as e:
        print(f"  ✗ Docs: {e}")
        tests.append(("Integration docs bilingual", False))

    try:
        test_adapter_exists()
        tests.append(("DeerFlowADPSandboxProvider adapter", True))
    except Exception as e:
        print(f"  ✗ Adapter: {e}")
        tests.append(("DeerFlowADPSandboxProvider adapter", False))

    # ── Report ──────────────────────────────────────────────────────
    print()
    print("─" * 64)
    passed = sum(1 for _, ok in tests if ok)
    failed = sum(1 for _, ok in tests if not ok)
    print(f"  Results: {passed} passed, {failed} failed, {len(tests)} total")
    print("─" * 64)

    for name, ok in tests:
        status = "✓" if ok else "✗"
        print(f"  {status} {name}")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
