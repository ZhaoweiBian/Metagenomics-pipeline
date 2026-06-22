"""Pipeline 邮件通知辅助模块，复用 lib/common.sh 中的 send_notification。"""
import os
import subprocess


def send_notification(subject: str, body: str) -> None:
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
    )
