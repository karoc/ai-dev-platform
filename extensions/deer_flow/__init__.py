"""
ADP-OS Deer-Flow Sandbox Extension

Provides a SandboxProvider adapter that allows deer-flow agents to use
ADP-OS VMs as sandbox backends via SSH + the ADP-OS MCP protocol.

Classes:
    DeerFlowADPSandboxProvider — SandboxProvider implementation for ADP-OS
    ADPSSHSandbox             — Sandbox implementation backed by SSH to ADP-OS VMs

Usage:
    from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

    provider = DeerFlowADPSandboxProvider(adp_home="/path/to/ai-dev-platform")
    sandbox_id = provider.acquire(thread_id="thread-123")
    sandbox = provider.get(sandbox_id)
    result = sandbox.execute_command("pip install requests")
    provider.release(sandbox_id)
"""

from .deerflow_adp_sandbox import (
    DeerFlowADPSandboxProvider,
    ADPSSHSandbox,
    SandboxProvider,
    Sandbox,
    GrepMatch,
)

__all__ = [
    "DeerFlowADPSandboxProvider",
    "ADPSSHSandbox",
    "SandboxProvider",
    "Sandbox",
    "GrepMatch",
]
