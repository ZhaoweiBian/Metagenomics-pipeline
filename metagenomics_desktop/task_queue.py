"""任务队列管理。"""
from __future__ import annotations

import json
import uuid
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List

QUEUE_FILE = Path.home() / ".metagenomics_desktop" / "task_queue.json"


@dataclass
class QueueTask:
    task_id: str
    label: str
    run_mode: str
    step_id: str = ""
    from_step: str = ""
    to_step: str = ""
    phase: str = ""
    status: str = "pending"  # pending | running | done | failed | cancelled

    @staticmethod
    def from_settings(settings: dict) -> QueueTask:
        label = _make_label(settings)
        return QueueTask(
            task_id=str(uuid.uuid4())[:8],
            label=label,
            run_mode=settings["run_mode"],
            step_id=settings.get("step_id", ""),
            from_step=settings.get("from_step", ""),
            to_step=settings.get("to_step", ""),
            phase=settings.get("phase", ""),
        )


def _make_label(settings: dict) -> str:
    mode = settings["run_mode"]
    if mode == "phase":
        return f"阶段: {settings.get('phase', '')}"
    if mode == "step":
        return f"单步: {settings.get('step_id', '')}"
    if mode == "range":
        return f"区间: {settings.get('from_step', '')} → {settings.get('to_step', '')}"
    return "完整流程"


def load_queue() -> List[QueueTask]:
    if not QUEUE_FILE.exists():
        return []
    with open(QUEUE_FILE, encoding="utf-8") as f:
        raw = json.load(f)
    return [QueueTask(**item) for item in raw]


def save_queue(tasks: List[QueueTask]):
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(QUEUE_FILE, "w", encoding="utf-8") as f:
        json.dump([asdict(t) for t in tasks], f, indent=2, ensure_ascii=False)


def add_task(settings: dict) -> QueueTask:
    tasks = load_queue()
    task = QueueTask.from_settings(settings)
    tasks.append(task)
    save_queue(tasks)
    return task


def clear_finished(tasks: List[QueueTask]) -> List[QueueTask]:
    return [t for t in tasks if t.status in ("pending", "running")]


def next_pending(tasks: List[QueueTask]) -> QueueTask | None:
    for t in tasks:
        if t.status == "pending":
            return t
    return None
