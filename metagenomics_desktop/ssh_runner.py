"""SSH 连接、文件传输与远程命令执行。"""
from __future__ import annotations

import shlex
import socket
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional, Tuple

try:
    import paramiko
except ImportError as exc:
    raise ImportError("请先安装 paramiko: pip install paramiko") from exc

from task_queue import QueueTask


LogCallback = Callable[[str], None]
DoneCallback = Callable[[int], None]


@dataclass
class ServerConfig:
    host: str
    port: int
    username: str
    auth_method: str
    private_key: str
    password: str
    remote_script_dir: str
    project_root: str
    enable_email: bool


@dataclass
class DiskInfo:
    filesystem: str
    size: str
    used: str
    avail: str
    use_pct: str
    mount: str


class SSHRunner:
    def __init__(self):
        self._client: Optional[paramiko.SSHClient] = None
        self._channel = None
        self._thread: Optional[threading.Thread] = None
        self._stop_flag = threading.Event()

    def _connect_kwargs(self, cfg: ServerConfig, timeout: int = 15) -> dict:
        kwargs = {
            "hostname": cfg.host,
            "port": cfg.port,
            "username": cfg.username,
            "timeout": timeout,
            "allow_agent": True,
            "look_for_keys": True,
        }
        if cfg.auth_method == "password":
            kwargs["password"] = cfg.password
        else:
            key_path = cfg.private_key.strip()
            if not key_path:
                raise ValueError("请填写 SSH 私钥路径")
            kwargs["key_filename"] = key_path
        return kwargs

    def connect(self, cfg: ServerConfig, timeout: int = 15) -> str:
        self.disconnect()
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(**self._connect_kwargs(cfg, timeout))
        self._client = client
        stdin, stdout, stderr = client.exec_command("hostname && pwd", timeout=timeout)
        out = stdout.read().decode("utf-8", errors="replace").strip()
        err = stderr.read().decode("utf-8", errors="replace").strip()
        if stdout.channel.recv_exit_status() != 0:
            raise RuntimeError(err or "连接测试失败")
        return out

    def disconnect(self):
        self._stop_flag.set()
        if self._channel is not None:
            try:
                self._channel.close()
            except Exception:
                pass
            self._channel = None
        if self._client is not None:
            try:
                self._client.close()
            except Exception:
                pass
            self._client = None

    def stop(self):
        self._stop_flag.set()
        if self._channel is not None:
            try:
                self._channel.close()
            except Exception:
                pass

    def _ensure_client(self, cfg: ServerConfig):
        if self._client is None:
            self.connect(cfg)

    def _exec(self, command: str, timeout: int = 120) -> Tuple[int, str, str]:
        if self._client is None:
            raise RuntimeError("请先连接服务器")
        stdin, stdout, stderr = self._client.exec_command(command, timeout=timeout)
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        code = stdout.channel.recv_exit_status()
        return code, out, err

    @staticmethod
    def build_pipeline_command(cfg: ServerConfig, run_mode: str, **kwargs) -> str:
        script_dir = shlex.quote(cfg.remote_script_dir)
        env_parts = [f"PROJECT_ROOT={shlex.quote(cfg.project_root)}"]
        if cfg.enable_email:
            env_parts.append("ENABLE_EMAIL=true")

        if run_mode == "step":
            flag = f"--step {shlex.quote(kwargs['step_id'])}"
        elif run_mode == "range":
            flag = f"--from {shlex.quote(kwargs['from_step'])} --to {shlex.quote(kwargs['to_step'])}"
        elif run_mode == "phase":
            flag = f"--phase {shlex.quote(kwargs['phase'])}"
        elif run_mode == "all":
            flag = "--all"
        else:
            raise ValueError(f"未知运行模式: {run_mode}")

        env_str = " ".join(env_parts)
        return f"cd {script_dir} && {env_str} bash -lc './run_pipeline.sh {flag}'"

    @staticmethod
    def build_task_command(cfg: ServerConfig, task: QueueTask) -> str:
        return SSHRunner.build_pipeline_command(
            cfg,
            task.run_mode,
            step_id=task.step_id,
            from_step=task.from_step,
            to_step=task.to_step,
            phase=task.phase,
        )

    def upload_file(self, cfg: ServerConfig, local_path: str, remote_path: str):
        self._ensure_client(cfg)
        local = Path(local_path)
        if not local.is_file():
            raise FileNotFoundError(f"本地文件不存在: {local_path}")
        remote_dir = str(Path(remote_path).parent).replace("\\", "/")
        self._exec(f"mkdir -p {shlex.quote(remote_dir)}")
        sftp = self._client.open_sftp()
        try:
            sftp.put(str(local), remote_path)
        finally:
            sftp.close()

    def check_disk_space(self, cfg: ServerConfig) -> DiskInfo:
        self._ensure_client(cfg)
        cmd = f"df -h {shlex.quote(cfg.project_root)} | tail -1"
        code, out, err = self._exec(cmd)
        if code != 0 or not out.strip():
            code, out, err = self._exec("df -h / | tail -1")
        parts = out.split()
        if len(parts) < 6:
            raise RuntimeError(err or "无法解析磁盘信息")
        return DiskInfo(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])

    def fetch_samplelist_preview(self, cfg: ServerConfig, limit: int = 20) -> Tuple[int, List[str]]:
        self._ensure_client(cfg)
        remote = f"{cfg.project_root.rstrip('/')}/samplelist"
        cmd = (
            f"if [[ -f {shlex.quote(remote)} ]]; then "
            f"awk 'NF && $0 !~ /^#/ {{print}}' {shlex.quote(remote)} | wc -l; "
            f"awk 'NF && $0 !~ /^#/ {{print}}' {shlex.quote(remote)} | head -n {limit}; "
            f"else echo 0; fi"
        )
        code, out, err = self._exec(cmd)
        if code != 0:
            raise RuntimeError(err or "读取 samplelist 失败")
        lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
        if not lines:
            return 0, []
        try:
            return int(lines[0]), lines[1:]
        except ValueError:
            return 0, lines

    def check_step_status(self, cfg: ServerConfig) -> str:
        self._ensure_client(cfg)
        checker = f"{cfg.remote_script_dir.rstrip('/')}/metagenomics_desktop/remote_check_status.sh"
        cmd = f"bash {shlex.quote(checker)} {shlex.quote(cfg.project_root)}"
        code, out, err = self._exec(cmd, timeout=180)
        if code != 0:
            raise RuntimeError(err or out or "状态检查失败")
        return out

    def fetch_remote_list(self, cfg: ServerConfig, timeout: int = 30) -> str:
        self._ensure_client(cfg)
        cmd = (
            f"cd {shlex.quote(cfg.remote_script_dir)} && "
            f"PROJECT_ROOT={shlex.quote(cfg.project_root)} "
            f"bash -lc './run_pipeline.sh --list'"
        )
        code, out, err = self._exec(cmd, timeout=timeout)
        if code != 0:
            raise RuntimeError(err or "获取步骤列表失败")
        return out

    def run_command_async(self, command: str, on_log: LogCallback, on_done: DoneCallback):
        if self._client is None:
            raise RuntimeError("请先连接服务器")

        self._stop_flag.clear()

        def worker():
            exit_code = 1
            try:
                self._channel = self._client.get_transport().open_session()
                self._channel.get_pty(term="xterm", width=120, height=40)
                self._channel.exec_command(command)
                while True:
                    if self._stop_flag.is_set():
                        break
                    if self._channel.recv_ready():
                        data = self._channel.recv(4096).decode("utf-8", errors="replace")
                        if data:
                            on_log(data)
                    if self._channel.exit_status_ready():
                        break
                while self._channel.recv_ready():
                    data = self._channel.recv(4096).decode("utf-8", errors="replace")
                    if data:
                        on_log(data)
                exit_code = self._channel.recv_exit_status() if self._channel.exit_status_ready() else 1
            except (socket.error, paramiko.SSHException) as exc:
                on_log(f"\n[错误] {exc}\n")
                exit_code = 1
            finally:
                self._channel = None
                on_done(exit_code)

        self._thread = threading.Thread(target=worker, daemon=True)
        self._thread.start()
