"""Pipeline 邮件通知辅助模块，复用 lib/common.sh 中的 send_notification。"""
import os
import re
import subprocess


def _caller_script_env() -> dict:
    """为 Python 步骤补全 PIPELINE_STEP_ID / PIPELINE_SCRIPT_NAME（由 common.sh 统一格式化邮件）。"""
    env = os.environ.copy()
    if env.get("PIPELINE_SCRIPT_NAME"):
        return env
    import inspect

    for frame in inspect.stack()[1:]:
        path = frame.filename.replace("\\", "/")
        if not path.endswith(".py") or "/lib/" in path:
            continue
        script = os.path.basename(path)
        env["PIPELINE_SCRIPT_NAME"] = script
        if not env.get("PIPELINE_STEP_ID"):
            match = re.match(r"^(\d+\.\d+)_", script)
            if match:
                env["PIPELINE_STEP_ID"] = match.group(1)
        break
    return env


def send_notification(subject: str, body: str) -> None:
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    env = _caller_script_env()
    subprocess.run(
        [
            "bash",
            "-c",
            f'source "{script_dir}/config.sh" && '
            f'source "{script_dir}/lib/common.sh" && '
            "send_notification \"$1\" \"$2\"",
            "_",
            subject,
            body,
        ],
        check=False,
        env=env,
    )
