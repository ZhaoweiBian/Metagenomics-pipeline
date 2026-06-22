"""步骤状态解析。"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List

from pipeline_data import PIPELINE_STEPS

STATUS_LABEL = {
    "done": "已完成",
    "pending": "未开始",
    "partial": "部分完成",
    "running": "运行中",
}


@dataclass
class StepStatus:
    step_id: str
    description: str
    status: str
    detail: str


def parse_status_output(text: str) -> Dict[str, StepStatus]:
    result: Dict[str, StepStatus] = {}
    desc_map = {s[0]: s[1] for s in PIPELINE_STEPS}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        sid, status, detail = parts[0], parts[1], parts[2]
        result[sid] = StepStatus(sid, desc_map.get(sid, ""), status, detail)
    for sid, desc in PIPELINE_STEPS:
        if sid not in result:
            result[sid] = StepStatus(sid, desc, "pending", "未检测")
    return result


def suggest_next_step(statuses: Dict[str, StepStatus]) -> str | None:
    for sid, _ in PIPELINE_STEPS:
        st = statuses.get(sid)
        if st and st.status != "done":
            return sid
    return None


def completion_summary(statuses: Dict[str, StepStatus]) -> str:
    done = sum(1 for s in PIPELINE_STEPS if statuses.get(s[0], StepStatus(s[0], "", "pending", "")).status == "done")
    return f"{done}/{len(PIPELINE_STEPS)} 步已完成"
