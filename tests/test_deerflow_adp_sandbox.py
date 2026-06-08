#!/usr/bin/env python3
"""Tests for ADP-OS Deer-Flow Sandbox Adapter."""
import json, sys, tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestGrepMatch:
    def test_create(self):
        from extensions.deer_flow.deerflow_adp_sandbox import GrepMatch
        m = GrepMatch(path="/tmp/test.py", line_number=42, line="hello world")
        assert m.path == "/tmp/test.py"
        assert m.line_number == 42
        assert m.line == "hello world"

    def test_immutable(self):
        from extensions.deer_flow.deerflow_adp_sandbox import GrepMatch
        m = GrepMatch(path="/tmp/test.py", line_number=1, line="")
        try:
            m.path = "/other"
            assert False
        except Exception:
            pass

    def test_repr(self):
        from extensions.deer_flow.deerflow_adp_sandbox import GrepMatch
        m = GrepMatch(path="/a/b.py", line_number=10, line="x")
        assert "b.py:10" in repr(m)


class TestABCs:
    def test_sandbox_abc_exists(self):
        from extensions.deer_flow.deerflow_adp_sandbox import Sandbox
        assert Sandbox is not None

    def test_shlex_quote_reexport(self):
        from extensions.deer_flow.deerflow_adp_sandbox import shlex_quote
        assert shlex_quote("a b") == "'a b'"

    def test_sandbox_is_abstract(self):
        from extensions.deer_flow.deerflow_adp_sandbox import Sandbox
        try:
            Sandbox("test")
            assert False
        except TypeError:
            pass

    def test_sandbox_has_eight_abstract_methods(self):
        from extensions.deer_flow.deerflow_adp_sandbox import Sandbox
        import inspect
        methods = [m for m in dir(Sandbox) if hasattr(getattr(Sandbox, m), "__isabstractmethod__")]
        expected = {"execute_command", "read_file", "download_file", "list_dir", "write_file", "glob", "grep", "update_file"}
        assert expected.issubset(set(methods)), f"Missing: {expected - set(methods)}"

    def test_sandbox_provider_has_three_abstract_methods(self):
        from extensions.deer_flow.deerflow_adp_sandbox import SandboxProvider
        import inspect
        methods = [m for m in dir(SandboxProvider) if hasattr(getattr(SandboxProvider, m), "__isabstractmethod__")]
        expected = {"acquire", "get", "release"}
        assert expected.issubset(set(methods)), f"Missing: {expected - set(methods)}"


def _mock_ssh_conn(host="192.168.242.135", port=22):
    conn = MagicMock()
    conn.host = host
    conn.port = port
    return conn


class TestADPSSHSandbox:
    def test_id_property(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        sb = ADPSSHSandbox("agent", _mock_ssh_conn())
        assert sb.id == "agent"

    def test_isinstance_of_sandbox(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox, Sandbox
        sb = ADPSSHSandbox("test", _mock_ssh_conn())
        assert isinstance(sb, Sandbox)

    def test_execute_command(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command_output.return_value = "Python 3.11.5"
        sb = ADPSSHSandbox("agent", conn)
        result = sb.execute_command("python --version")
        assert result == "Python 3.11.5"

    def test_read_file_success(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("hello world\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        result = sb.read_file("/tmp/test.txt")
        assert result == "hello world\n"

    def test_read_file_not_found(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("", "No such file", 1)
        sb = ADPSSHSandbox("agent", conn)
        try:
            sb.read_file("/nonexistent")
            assert False
        except OSError:
            pass

    def test_write_file(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        sb.write_file("/tmp/hello.py", "print('hi')")
        assert conn.exec_command.called
        assert "base64" in conn.exec_command.call_args[0][0]

    def test_write_file_append(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        sb.write_file("/tmp/log.txt", "new line\n", append=True)
        assert ">>" in conn.exec_command.call_args[0][0]

    def test_write_file_error(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("", "Permission denied", 1)
        sb = ADPSSHSandbox("agent", conn)
        try:
            sb.write_file("/root/secret", "data")
            assert False
        except OSError:
            pass

    def test_list_dir(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("/tmp\n/tmp/file1.txt\n/tmp/file2.py\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        result = sb.list_dir("/tmp", max_depth=2)
        assert len(result) == 3

    def test_glob(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("/tmp/a.py\n/tmp/b.py\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        matches, truncated = sb.glob("/tmp", "*.py")
        assert len(matches) == 2
        assert not truncated

    def test_glob_truncated(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        lines = [f"/tmp/file_{i}.py" for i in range(201)]
        conn.exec_command.return_value = ("\n".join(lines), "", 0)
        sb = ADPSSHSandbox("agent", conn)
        matches, truncated = sb.glob("/tmp", "*.py", max_results=200)
        assert len(matches) == 200
        assert truncated

    def test_grep(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("/tmp/test.py:42:TODO: fix\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        matches, truncated = sb.grep("/tmp", "TODO")
        assert len(matches) == 1
        assert matches[0].path == "/tmp/test.py"
        assert matches[0].line_number == 42
        assert not truncated

    def test_grep_literal(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("/tmp/x:1:foo.bar\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        sb.grep("/tmp", "foo.bar", literal=True)
        assert "-F" in conn.exec_command.call_args[0][0]

    def test_download_file(self):
        import base64
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        data = b"binary content here"
        encoded = base64.b64encode(data).decode("ascii")
        conn.exec_command.return_value = (encoded + "\n", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        result = sb.download_file("/tmp/data.bin")
        assert result == data

    def test_update_file(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        conn.exec_command.return_value = ("", "", 0)
        sb = ADPSSHSandbox("agent", conn)
        sb.update_file("/tmp/data.bin", b"binary data")
        assert conn.exec_command.called

    def test_close(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPSSHSandbox
        conn = _mock_ssh_conn()
        sb = ADPSSHSandbox("agent", conn)
        sb.close()
        conn.close.assert_called_once()


class TestThreadRuntimeRegistry:
    def test_default_mapping_none(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            r = ThreadRuntimeRegistry(Path(td) / "registry.json")
            assert r.get(None) == "agent"

    def test_fallback_to_thread_id(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            r = ThreadRuntimeRegistry(Path(td) / "registry.json")
            assert r.get("my-thread-123") == "my-thread-123"

    def test_set_and_get(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            r = ThreadRuntimeRegistry(Path(td) / "registry.json")
            r.set("thread-abc", "sandbox")
            assert r.get("thread-abc") == "sandbox"

    def test_persistence(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "registry.json"
            r1 = ThreadRuntimeRegistry(path)
            r1.set("t1", "agent")
            r1.save()
            r2 = ThreadRuntimeRegistry(path)
            assert r2.get("t1") == "agent"

    def test_remove(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            r = ThreadRuntimeRegistry(Path(td) / "registry.json")
            r.set("t1", "agent")
            r.remove("t1")
            assert r.get("t1") == "t1"

    def test_list_runtimes(self):
        from extensions.deer_flow.deerflow_adp_sandbox import ThreadRuntimeRegistry
        with tempfile.TemporaryDirectory() as td:
            r = ThreadRuntimeRegistry(Path(td) / "registry.json")
            r.set("t1", "agent")
            r.set("t2", "sandbox")
            runtimes = r.list_runtimes()
            assert "agent" in runtimes
            assert "sandbox" in runtimes


class TestSSHConnection:
    def test_init(self):
        from extensions.deer_flow.deerflow_adp_sandbox import SSHConnection
        conn = SSHConnection("192.168.242.135", port=22, username="adp", password="adp")
        assert conn.host == "192.168.242.135"

    def test_subprocess_exec_basic(self):
        from extensions.deer_flow.deerflow_adp_sandbox import SSHConnection
        conn = SSHConnection("192.168.1.1")
        with patch("subprocess.run") as mock_run:
            mock_result = MagicMock()
            mock_result.stdout = "hello"
            mock_result.stderr = ""
            mock_result.returncode = 0
            mock_run.return_value = mock_result
            stdout, stderr, exit_code = conn._subprocess_exec("echo hi")
            assert stdout == "hello"
            assert exit_code == 0

    def test_subprocess_exec_timeout(self):
        from extensions.deer_flow.deerflow_adp_sandbox import SSHConnection
        import subprocess as sp
        conn = SSHConnection("192.168.1.1")
        with patch("subprocess.run", side_effect=sp.TimeoutExpired("ssh", 30)):
            stdout, stderr, exit_code = conn._subprocess_exec("sleep 999")
            assert exit_code == -1


class TestADPCLI:
    @patch("pathlib.Path.exists", return_value=True)
    @patch("pathlib.Path.read_text")
    def test_load_topology(self, mock_read, mock_exists):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPCLI
        mock_read.return_value = json.dumps({"agent": {"static_ip": "192.168.242.135", "ssh_port": 22}})
        cli = ADPCLI("/fake/adp")
        topo = cli.load_topology()
        assert topo["agent"]["static_ip"] == "192.168.242.135"

    @patch("pathlib.Path.exists", return_value=True)
    @patch("pathlib.Path.read_text")
    def test_get_runtime_ssh_info(self, mock_read, mock_exists):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPCLI
        mock_read.return_value = json.dumps({"agent": {"static_ip": "192.168.242.135", "ssh_port": 22}})
        cli = ADPCLI("/fake/adp")
        info = cli.get_runtime_ssh_info("agent")
        assert info["ip"] == "192.168.242.135"
        assert info["port"] == 22

    @patch("pathlib.Path.exists", return_value=True)
    @patch("pathlib.Path.read_text")
    def test_get_runtime_ssh_info_unknown(self, mock_read, mock_exists):
        from extensions.deer_flow.deerflow_adp_sandbox import ADPCLI
        mock_read.return_value = json.dumps({})
        cli = ADPCLI("/fake/adp")
        info = cli.get_runtime_ssh_info("nonexistent")
        assert info["ip"] == ""


def _mock_cli_success(status_text="agent    running   192.168.242.135  reachable  healthy"):
    cli = MagicMock()
    cli.status.return_value = {"stdout": status_text, "stderr": "", "exit_code": 0, "success": True}
    cli.up.return_value = {"stdout": "VM started", "stderr": "", "exit_code": 0, "success": True}
    cli.stop.return_value = {"stdout": "VM stopped", "stderr": "", "exit_code": 0, "success": True}
    cli.get_runtime_ssh_info.return_value = {"ip": "192.168.242.135", "port": 22, "user": "adp", "password": "adp"}
    return cli


class TestDeerFlowADPSandboxProvider:
    def test_init(self):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        with patch("pathlib.Path.exists", return_value=True), \
             patch("pathlib.Path.read_text", return_value="{}"):
            p = DeerFlowADPSandboxProvider("/fake/adp")
            assert p.adp_home == Path("/fake/adp")
            assert p.pool_available == 0

    def test_smoke_import(self):
        import extensions.deer_flow.deerflow_adp_sandbox as mod
        assert mod.DeerFlowADPSandboxProvider is not None

    @patch("extensions.deer_flow.deerflow_adp_sandbox.ADPCLI")
    def test_acquire_new_vm(self, mock_cli_cls):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        cli = _mock_cli_success()
        cli.status.return_value = {"success": False, "running": False}  # VM not yet running
        mock_cli_cls.return_value = cli
        with tempfile.TemporaryDirectory() as td:
            p = DeerFlowADPSandboxProvider(adp_home="/fake/adp", pool_size=0, registry_path=Path(td) / "reg.json")
            p._wait_for_ssh = MagicMock()
            sandbox_id = p.acquire(thread_id="thread-1")
            assert sandbox_id == "thread-1"
            cli.up.assert_called()

    @patch("extensions.deer_flow.deerflow_adp_sandbox.ADPCLI")
    @patch("extensions.deer_flow.deerflow_adp_sandbox.SSHConnection")
    def test_get_creates_sandbox(self, mock_ssh_cls, mock_cli_cls):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider, ADPSSHSandbox
        cli = _mock_cli_success()
        mock_cli_cls.return_value = cli
        mock_ssh = MagicMock()
        mock_ssh.host = "192.168.242.135"
        mock_ssh_cls.return_value = mock_ssh
        with tempfile.TemporaryDirectory() as td:
            p = DeerFlowADPSandboxProvider(adp_home="/fake/adp", pool_size=0, registry_path=Path(td) / "reg.json")
            sandbox = p.get("agent")
            assert isinstance(sandbox, ADPSSHSandbox)
            assert sandbox.id == "agent"

    @patch("extensions.deer_flow.deerflow_adp_sandbox.ADPCLI")
    @patch("extensions.deer_flow.deerflow_adp_sandbox.SSHConnection")
    def test_get_caches_sandbox(self, mock_ssh_cls, mock_cli_cls):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        cli = _mock_cli_success()
        mock_cli_cls.return_value = cli
        mock_ssh = MagicMock()
        mock_ssh.host = "192.168.242.135"
        mock_ssh_cls.return_value = mock_ssh
        with tempfile.TemporaryDirectory() as td:
            p = DeerFlowADPSandboxProvider(adp_home="/fake/adp", pool_size=0, registry_path=Path(td) / "reg.json")
            sb1 = p.get("agent")
            sb2 = p.get("agent")
            assert sb1 is sb2

    @patch("extensions.deer_flow.deerflow_adp_sandbox.ADPCLI")
    def test_release_stops_vm(self, mock_cli_cls):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        cli = _mock_cli_success()
        mock_cli_cls.return_value = cli
        with tempfile.TemporaryDirectory() as td:
            p = DeerFlowADPSandboxProvider(adp_home="/fake/adp", pool_size=0, registry_path=Path(td) / "reg.json")
            p.release("agent")
            cli.stop.assert_called_once_with("agent")

    def test_extract_ip(self):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        ip = DeerFlowADPSandboxProvider._extract_ip("agent    running   192.168.242.135  reachable  healthy", "agent")
        assert ip == "192.168.242.135"

    def test_extract_ip_not_found(self):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        ip = DeerFlowADPSandboxProvider._extract_ip("agent    stopped", "agent")
        assert ip is None


class TestVMPool:
    def test_empty_pool_acquire_returns_none(self):
        from extensions.deer_flow.deerflow_adp_sandbox import VMPool, ThreadRuntimeRegistry
        cli = _mock_cli_success()
        with tempfile.TemporaryDirectory() as td:
            reg = ThreadRuntimeRegistry(Path(td) / "reg.json")
            pool = VMPool(cli, reg, pool_size=2)
            assert pool.acquire() is None

    def test_available_zero_initially(self):
        from extensions.deer_flow.deerflow_adp_sandbox import VMPool, ThreadRuntimeRegistry
        cli = _mock_cli_success()
        with tempfile.TemporaryDirectory() as td:
            reg = ThreadRuntimeRegistry(Path(td) / "reg.json")
            pool = VMPool(cli, reg, pool_size=2)
            assert pool.available == 0


class TestFullLifecycle:
    @patch("extensions.deer_flow.deerflow_adp_sandbox.SSHConnection")
    @patch("extensions.deer_flow.deerflow_adp_sandbox.ADPCLI")
    def test_acquire_get_use_release(self, mock_cli_cls, mock_ssh_cls):
        from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider
        cli = _mock_cli_success()
        mock_cli_cls.return_value = cli
        mock_ssh = MagicMock()
        mock_ssh.host = "192.168.242.135"
        mock_ssh.exec_command.return_value = ("", "", 0)
        mock_ssh.exec_command_output.return_value = "Python 3.11.5"
        mock_ssh_cls.return_value = mock_ssh
        with tempfile.TemporaryDirectory() as td:
            p = DeerFlowADPSandboxProvider(adp_home="/fake/adp", pool_size=0, registry_path=Path(td) / "reg.json")
            p._wait_for_ssh = MagicMock()
            sid = p.acquire("my-thread")
            assert sid is not None
            sb = p.get(sid)
            assert sb is not None
            output = sb.execute_command("python --version")
            assert output == "Python 3.11.5"
            p.release(sid)
            cli.stop.assert_called()


def run_tests():
    import traceback
    test_classes = [
        TestGrepMatch, TestABCs, TestADPSSHSandbox, TestThreadRuntimeRegistry,
        TestSSHConnection, TestADPCLI, TestDeerFlowADPSandboxProvider, TestVMPool, TestFullLifecycle,
    ]
    total = passed = failed = 0
    for cls in test_classes:
        instance = cls()
        for name in sorted(dir(instance)):
            if name.startswith("test_"):
                total += 1
                try:
                    getattr(instance, name)()
                    passed += 1
                    print(f"  OK  {cls.__name__}.{name}")
                except Exception as e:
                    failed += 1
                    print(f"  FAIL {cls.__name__}.{name}: {e}")
                    traceback.print_exc()
    print(f"\n{'='*60}")
    print(f"Results: {passed}/{total} passed, {failed} failed")
    if failed:
        print("FAILED"); sys.exit(1)
    else:
        print("OK")

if __name__ == "__main__":
    run_tests()
