#!/usr/bin/env python3
"""宏基因组 Pipeline 桌面客户端 — 图形化远程分析控制台。"""
from __future__ import annotations

import queue
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext, ttk

from config_manager import load_settings, save_settings
from pipeline_data import PIPELINE_PHASES, PIPELINE_STEPS, STEP_IDS
from ssh_runner import SSHRunner, ServerConfig
from step_status import (
    STATUS_LABEL,
    completion_summary,
    parse_status_output,
    suggest_next_step,
)
from task_queue import QueueTask, add_task, load_queue, next_pending, save_queue


class MetagenomicsDesktopApp(tk.Tk):
    STATUS_TAGS = {
        "done": ("done", {"foreground": "#1a7f37"}),
        "pending": ("pending", {"foreground": "#888888"}),
        "partial": ("partial", {"foreground": "#b8860b"}),
        "running": ("running", {"foreground": "#0969da"}),
    }

    def __init__(self):
        super().__init__()
        self.title("宏基因组 Pipeline 分析平台")
        self.geometry("1080x780")
        self.minsize(960, 680)

        self.runner = SSHRunner()
        self.log_queue: queue.Queue = queue.Queue()
        self.settings = load_settings()
        self.tasks: list[QueueTask] = load_queue()
        self.step_statuses = {}
        self._running = False
        self._queue_mode = False
        self._current_task: QueueTask | None = None

        self._build_ui()
        self._load_form()
        self._refresh_queue_view()
        self.after(100, self._poll_log_queue)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ------------------------------------------------------------------ UI
    def _build_ui(self):
        header = ttk.Frame(self, padding=(12, 8))
        header.pack(fill=tk.X)
        ttk.Label(
            header,
            text="宏基因组分析平台",
            font=("", 14, "bold"),
        ).pack(side=tk.LEFT)
        self.summary_var = tk.StringVar(value="请先在「① 连接」页测试服务器连接")
        ttk.Label(header, textvariable=self.summary_var, foreground="#555").pack(side=tk.RIGHT)

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 4))

        self.tab_conn = ttk.Frame(self.notebook, padding=12)
        self.tab_project = ttk.Frame(self.notebook, padding=12)
        self.tab_progress = ttk.Frame(self.notebook, padding=12)
        self.tab_queue = ttk.Frame(self.notebook, padding=12)
        self.tab_log = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.tab_conn, text="① 连接")
        self.notebook.add(self.tab_project, text="② 项目准备")
        self.notebook.add(self.tab_progress, text="③ 运行进度")
        self.notebook.add(self.tab_queue, text="④ 任务队列")
        self.notebook.add(self.tab_log, text="⑤ 日志")

        self._build_connection_tab()
        self._build_project_tab()
        self._build_progress_tab()
        self._build_queue_tab()
        self._build_log_tab()

        bottom = ttk.Frame(self, padding=(8, 0, 8, 8))
        bottom.pack(fill=tk.X)
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(bottom, textvariable=self.status_var).pack(side=tk.LEFT)
        ttk.Button(bottom, text="保存配置", command=self._save_config).pack(side=tk.RIGHT, padx=4)
        ttk.Button(bottom, text="退出", command=self._on_close).pack(side=tk.RIGHT)

    def _build_connection_tab(self):
        f = self.tab_conn
        canvas = ttk.Frame(f)
        canvas.pack(fill=tk.BOTH, expand=True)

        row = 0

        def title(text):
            nonlocal row
            ttk.Label(canvas, text=text, font=("", 10, "bold")).grid(
                row=row, column=0, columnspan=3, sticky="w", pady=(10, 4)
            )
            row += 1

        def field(label, var, width=42, browse=False, show=None):
            nonlocal row
            ttk.Label(canvas, text=label).grid(row=row, column=0, sticky="w", pady=3)
            ttk.Entry(canvas, textvariable=var, width=width, show=show).grid(
                row=row, column=1, sticky="ew", padx=4, pady=3
            )
            if browse:
                ttk.Button(canvas, text="浏览…", command=lambda v=var: self._browse_file(v)).grid(
                    row=row, column=2, sticky="w"
                )
            row += 1

        title("SSH 登录")
        self.var_host = tk.StringVar()
        self.var_port = tk.StringVar(value="22")
        self.var_user = tk.StringVar()
        self.var_auth = tk.StringVar(value="key")
        self.var_key = tk.StringVar()
        self.var_password = tk.StringVar()
        field("服务器地址", self.var_host)
        field("端口", self.var_port, width=10)
        field("用户名", self.var_user)
        auth = ttk.Frame(canvas)
        auth.grid(row=row, column=0, columnspan=3, sticky="w")
        ttk.Radiobutton(auth, text="SSH 私钥", variable=self.var_auth, value="key").pack(side=tk.LEFT)
        ttk.Radiobutton(auth, text="密码", variable=self.var_auth, value="password").pack(side=tk.LEFT, padx=10)
        row += 1
        field("私钥路径", self.var_key, browse=True)
        field("密码", self.var_password, show="*")

        title("服务器路径")
        self.var_script_dir = tk.StringVar()
        self.var_project_root = tk.StringVar()
        field("Pipeline 脚本目录", self.var_script_dir)
        field("项目根目录 PROJECT_ROOT", self.var_project_root)

        self.var_email = tk.BooleanVar()
        ttk.Checkbutton(canvas, text="任务完成后发送邮件通知", variable=self.var_email).grid(
            row=row, column=0, columnspan=3, sticky="w", pady=6
        )
        row += 1

        btns = ttk.Frame(canvas)
        btns.grid(row=row, column=0, columnspan=3, sticky="w", pady=10)
        ttk.Button(btns, text="测试连接", command=self._test_connection).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(btns, text="断开", command=self._disconnect).pack(side=tk.LEFT)
        ttk.Button(btns, text="下一步：项目准备 →", command=lambda: self.notebook.select(self.tab_project)).pack(
            side=tk.LEFT, padx=16
        )
        canvas.columnconfigure(1, weight=1)

    def _build_project_tab(self):
        f = self.tab_project
        top = ttk.LabelFrame(f, text="样本列表 (samplelist)", padding=10)
        top.pack(fill=tk.X, pady=(0, 10))

        path_row = ttk.Frame(top)
        path_row.pack(fill=tk.X)
        ttk.Label(path_row, text="本地文件").pack(side=tk.LEFT)
        self.var_local_samplelist = tk.StringVar()
        ttk.Entry(path_row, textvariable=self.var_local_samplelist).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)
        ttk.Button(path_row, text="选择…", command=self._pick_samplelist).pack(side=tk.LEFT)
        ttk.Button(path_row, text="上传到服务器", command=self._upload_samplelist).pack(side=tk.LEFT, padx=6)

        self.sample_info_var = tk.StringVar(value="尚未检查服务器上的 samplelist")
        ttk.Label(top, textvariable=self.sample_info_var, foreground="#444").pack(anchor="w", pady=6)
        self.sample_preview = scrolledtext.ScrolledText(top, height=6, font=("Consolas", 9))
        self.sample_preview.pack(fill=tk.X)
        ttk.Button(top, text="刷新服务器样本列表", command=self._refresh_samplelist).pack(anchor="e", pady=4)

        disk = ttk.LabelFrame(f, text="磁盘空间", padding=10)
        disk.pack(fill=tk.X, pady=(0, 10))
        self.disk_var = tk.StringVar(value="点击「检查磁盘」查看项目目录可用空间")
        ttk.Label(disk, textvariable=self.disk_var, font=("Consolas", 10)).pack(anchor="w")
        ttk.Button(disk, text="检查磁盘空间", command=self._check_disk).pack(anchor="e", pady=6)

        hint = ttk.LabelFrame(f, text="推荐流程", padding=10)
        hint.pack(fill=tk.BOTH, expand=True)
        ttk.Label(
            hint,
            text="1. 在「① 连接」页测试 SSH\n"
                 "2. 上传 samplelist（每行一个样本名）\n"
                 "3. 检查磁盘（组装/Binning 步骤需要数百 GB）\n"
                 "4. 在「③ 运行进度」查看已完成步骤，从断点继续\n"
                 "5. 在「④ 任务队列」添加并执行分析任务",
            justify=tk.LEFT,
        ).pack(anchor="w")

    def _build_progress_tab(self):
        f = self.tab_progress
        bar = ttk.Frame(f)
        bar.pack(fill=tk.X, pady=(0, 8))
        self.progress_summary_var = tk.StringVar(value="点击「刷新进度」扫描服务器输出文件")
        ttk.Label(bar, textvariable=self.progress_summary_var, font=("", 10, "bold")).pack(side=tk.LEFT)
        ttk.Button(bar, text="刷新进度", command=self._refresh_progress).pack(side=tk.RIGHT, padx=4)
        ttk.Button(bar, text="从建议步骤继续 →", command=self._use_suggested_step).pack(side=tk.RIGHT)

        cols = ("step_id", "desc", "status", "detail")
        self.status_tree = ttk.Treeview(f, columns=cols, show="headings", height=22)
        self.status_tree.heading("step_id", text="步骤")
        self.status_tree.heading("desc", text="说明")
        self.status_tree.heading("status", text="状态")
        self.status_tree.heading("detail", text="详情")
        self.status_tree.column("step_id", width=55, anchor="center")
        self.status_tree.column("desc", width=220)
        self.status_tree.column("status", width=80, anchor="center")
        self.status_tree.column("detail", width=420)
        self.status_tree.pack(fill=tk.BOTH, expand=True, side=tk.LEFT)
        scroll = ttk.Scrollbar(f, orient=tk.VERTICAL, command=self.status_tree.yview)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.status_tree.configure(yscrollcommand=scroll.set)
        for _, (tag, opts) in self.STATUS_TAGS.items():
            self.status_tree.tag_configure(tag, **opts)

    def _build_queue_tab(self):
        f = self.tab_queue
        cfg = ttk.LabelFrame(f, text="新建任务", padding=10)
        cfg.pack(fill=tk.X, pady=(0, 8))

        self.var_mode = tk.StringVar(value="phase")
        mode_row = ttk.Frame(cfg)
        mode_row.pack(fill=tk.X)
        for text, val in [
            ("按阶段", "phase"),
            ("单步", "step"),
            ("区间", "range"),
            ("全流程", "all"),
        ]:
            ttk.Radiobutton(mode_row, text=text, variable=self.var_mode, value=val, command=self._toggle_mode).pack(
                side=tk.LEFT, padx=4
            )

        self.mode_frame = ttk.Frame(cfg)
        self.mode_frame.pack(fill=tk.X, pady=6)
        self.phase_combo = ttk.Combobox(
            self.mode_frame,
            values=[f"{p[0]} — {p[1]}" for p in PIPELINE_PHASES],
            state="readonly",
            width=60,
        )
        self.step_combo = ttk.Combobox(
            self.mode_frame,
            values=[f"{s[0]} — {s[1]}" for s in PIPELINE_STEPS],
            state="readonly",
            width=60,
        )
        self.range_frame = ttk.Frame(self.mode_frame)
        self.from_combo = ttk.Combobox(self.range_frame, values=STEP_IDS, state="readonly", width=8)
        self.to_combo = ttk.Combobox(self.range_frame, values=STEP_IDS, state="readonly", width=8)
        ttk.Label(self.range_frame, text="从").pack(side=tk.LEFT)
        self.from_combo.pack(side=tk.LEFT, padx=4)
        ttk.Label(self.range_frame, text="到").pack(side=tk.LEFT)
        self.to_combo.pack(side=tk.LEFT, padx=4)
        self.all_label = ttk.Label(self.mode_frame, text="将运行全部步骤，耗时极长")

        btn_row = ttk.Frame(cfg)
        btn_row.pack(fill=tk.X, pady=4)
        ttk.Button(btn_row, text="加入队列", command=self._enqueue_task).pack(side=tk.LEFT, padx=(0, 8))
        ttk.Button(btn_row, text="立即运行（不排队）", command=self._start_single_run).pack(side=tk.LEFT)

        ql = ttk.LabelFrame(f, text="任务队列（按顺序执行，支持断点续跑）", padding=8)
        ql.pack(fill=tk.BOTH, expand=True)
        qcols = ("id", "label", "status")
        self.queue_tree = ttk.Treeview(ql, columns=qcols, show="headings", height=10)
        for c, t, w in [("id", "ID", 60), ("label", "任务", 360), ("status", "状态", 100)]:
            self.queue_tree.heading(c, text=t)
            self.queue_tree.column(c, width=w)
        self.queue_tree.pack(fill=tk.BOTH, expand=True, side=tk.LEFT)
        qscroll = ttk.Scrollbar(ql, orient=tk.VERTICAL, command=self.queue_tree.yview)
        qscroll.pack(side=tk.RIGHT, fill=tk.Y)
        self.queue_tree.configure(yscrollcommand=qscroll.set)

        self.var_stop_on_error = tk.BooleanVar(value=True)
        ctrl = ttk.Frame(f)
        ctrl.pack(fill=tk.X, pady=8)
        ttk.Checkbutton(ctrl, text="某任务失败后停止队列", variable=self.var_stop_on_error).pack(side=tk.LEFT)
        self.btn_run_queue = ttk.Button(ctrl, text="开始执行队列", command=self._start_queue_run)
        self.btn_run_queue.pack(side=tk.RIGHT, padx=4)
        self.btn_stop = ttk.Button(ctrl, text="停止", command=self._stop_run, state=tk.DISABLED)
        self.btn_stop.pack(side=tk.RIGHT, padx=4)
        ttk.Button(ctrl, text="删除选中", command=self._remove_selected_task).pack(side=tk.RIGHT, padx=4)
        ttk.Button(ctrl, text="清空已完成", command=self._clear_finished_tasks).pack(side=tk.RIGHT, padx=4)

        self._toggle_mode()

    def _build_log_tab(self):
        self.log_text = scrolledtext.ScrolledText(self.tab_log, wrap=tk.WORD, font=("Consolas", 9))
        self.log_text.pack(fill=tk.BOTH, expand=True)
        ttk.Button(self.tab_log, text="清空日志", command=lambda: self.log_text.delete("1.0", tk.END)).pack(anchor="e", pady=4)

    # ------------------------------------------------------------------ helpers
    def _toggle_mode(self):
        for w in self.mode_frame.winfo_children():
            w.pack_forget()
        mode = self.var_mode.get()
        if mode == "phase":
            self.phase_combo.pack(anchor="w")
        elif mode == "step":
            self.step_combo.pack(anchor="w")
        elif mode == "range":
            self.range_frame.pack(anchor="w")
        else:
            self.all_label.pack(anchor="w")

    def _browse_file(self, var: tk.StringVar):
        path = filedialog.askopenfilename()
        if path:
            var.set(path)

    def _pick_samplelist(self):
        path = filedialog.askopenfilename(
            title="选择 samplelist",
            filetypes=[("文本文件", "*.txt *.list"), ("所有文件", "*.*")],
        )
        if path:
            self.var_local_samplelist.set(path)

    def _collect_settings(self) -> dict:
        phase_idx = max(0, self.phase_combo.current())
        step_idx = max(0, self.step_combo.current())
        return {
            "host": self.var_host.get().strip(),
            "port": int(self.var_port.get().strip() or "22"),
            "username": self.var_user.get().strip(),
            "auth_method": self.var_auth.get(),
            "private_key": self.var_key.get().strip(),
            "password": self.var_password.get(),
            "remote_script_dir": self.var_script_dir.get().strip(),
            "project_root": self.var_project_root.get().strip(),
            "enable_email": self.var_email.get(),
            "local_samplelist": self.var_local_samplelist.get().strip(),
            "queue_stop_on_error": self.var_stop_on_error.get(),
            "run_mode": self.var_mode.get(),
            "step_id": PIPELINE_STEPS[step_idx][0],
            "from_step": self.from_combo.get().strip() or "7.3",
            "to_step": self.to_combo.get().strip() or "7.4",
            "phase": PIPELINE_PHASES[phase_idx][0],
        }

    def _load_form(self):
        s = self.settings
        self.var_host.set(s.get("host", ""))
        self.var_port.set(str(s.get("port", 22)))
        self.var_user.set(s.get("username", ""))
        self.var_auth.set(s.get("auth_method", "key"))
        self.var_key.set(s.get("private_key", ""))
        self.var_password.set(s.get("password", ""))
        self.var_script_dir.set(s.get("remote_script_dir", ""))
        self.var_project_root.set(s.get("project_root", ""))
        self.var_email.set(s.get("enable_email", False))
        self.var_local_samplelist.set(s.get("local_samplelist", ""))
        self.var_stop_on_error.set(s.get("queue_stop_on_error", True))
        self.var_mode.set(s.get("run_mode", "phase"))
        for i, p in enumerate(PIPELINE_PHASES):
            if p[0] == s.get("phase", "mag_function"):
                self.phase_combo.current(i)
                break
        for i, st in enumerate(PIPELINE_STEPS):
            if st[0] == s.get("step_id", "7.3"):
                self.step_combo.current(i)
                break
        self.from_combo.set(s.get("from_step", "7.3"))
        self.to_combo.set(s.get("to_step", "7.4"))
        self._toggle_mode()

    def _server_config(self) -> ServerConfig:
        s = self._collect_settings()
        if not s["host"] or not s["username"]:
            raise ValueError("请填写服务器地址和用户名")
        if not s["remote_script_dir"] or not s["project_root"]:
            raise ValueError("请填写脚本目录和项目根目录")
        return ServerConfig(**{k: s[k] for k in ServerConfig.__dataclass_fields__})

    def _save_config(self):
        self.settings = self._collect_settings()
        save_settings(self.settings)
        messagebox.showinfo("已保存", "配置已保存到 ~/.metagenomics_desktop/settings.json")

    def _save_config_silent(self):
        self.settings = self._collect_settings()
        save_settings(self.settings)

    def _append_log(self, text: str):
        self.log_text.insert(tk.END, text)
        self.log_text.see(tk.END)

    def _poll_log_queue(self):
        try:
            while True:
                item = self.log_queue.get_nowait()
                if isinstance(item, tuple) and item[0] == "done":
                    self._on_run_finished(item[1])
                else:
                    self._append_log(str(item))
        except queue.Empty:
            pass
        self.after(100, self._poll_log_queue)

    def _set_running(self, running: bool):
        self._running = running
        self.btn_stop.configure(state=tk.NORMAL if running else tk.DISABLED)
        self.btn_run_queue.configure(state=tk.DISABLED if running else tk.NORMAL)

    # ------------------------------------------------------------------ actions
    def _test_connection(self):
        try:
            cfg = self._server_config()
            info = self.runner.connect(cfg)
            self.status_var.set(f"已连接: {cfg.host}")
            self.summary_var.set(f"已连接 {cfg.host} — 请继续「② 项目准备」")
            messagebox.showinfo("连接成功", info)
        except Exception as exc:
            messagebox.showerror("连接失败", str(exc))

    def _disconnect(self):
        self.runner.disconnect()
        self.status_var.set("已断开")
        self.summary_var.set("未连接服务器")

    def _upload_samplelist(self):
        try:
            cfg = self._server_config()
            local = self.var_local_samplelist.get().strip()
            if not local:
                raise ValueError("请先选择本地 samplelist 文件")
            remote = f"{cfg.project_root.rstrip('/')}/samplelist"
            self.runner.upload_file(cfg, local, remote)
            self._append_log(f"\n[上传] {local} → {remote}\n")
            messagebox.showinfo("上传成功", f"已上传到:\n{remote}")
            self._refresh_samplelist()
        except Exception as exc:
            messagebox.showerror("上传失败", str(exc))

    def _refresh_samplelist(self):
        try:
            cfg = self._server_config()
            self.runner._ensure_client(cfg)
            count, preview = self.runner.fetch_samplelist_preview(cfg)
            self.sample_info_var.set(f"服务器 samplelist: {count} 个样本")
            self.sample_preview.delete("1.0", tk.END)
            if preview:
                self.sample_preview.insert(tk.END, "\n".join(preview))
                if count > len(preview):
                    self.sample_preview.insert(tk.END, f"\n… 共 {count} 个")
        except Exception as exc:
            messagebox.showerror("读取失败", str(exc))

    def _check_disk(self):
        try:
            cfg = self._server_config()
            self.runner._ensure_client(cfg)
            info = self.runner.check_disk_space(cfg)
            text = f"挂载: {info.mount}  总: {info.size}  已用: {info.used} ({info.use_pct})  可用: {info.avail}"
            self.disk_var.set(text)
            if info.avail.endswith("G"):
                try:
                    avail = float(info.avail.rstrip("GTi"))
                    if avail < 100:
                        messagebox.showwarning("空间不足", f"可用空间仅 {info.avail}，大型组装可能失败。\n建议 >200GB。")
                except ValueError:
                    pass
        except Exception as exc:
            messagebox.showerror("检查失败", str(exc))

    def _refresh_progress(self):
        def work():
            try:
                cfg = self._server_config()
                self.runner._ensure_client(cfg)
                raw = self.runner.check_step_status(cfg)
                statuses = parse_status_output(raw)
                self.after(0, lambda: self._apply_progress(statuses))
            except Exception as exc:
                self.after(0, lambda: messagebox.showerror("刷新失败", str(exc)))

        self.status_var.set("正在扫描进度…")
        threading.Thread(target=work, daemon=True).start()

    def _apply_progress(self, statuses: dict):
        self.step_statuses = statuses
        for item in self.status_tree.get_children():
            self.status_tree.delete(item)
        for sid, desc in PIPELINE_STEPS:
            st = statuses.get(sid)
            if not st:
                continue
            tag = st.status if st.status in self.STATUS_TAGS else "pending"
            self.status_tree.insert(
                "",
                tk.END,
                values=(sid, desc, STATUS_LABEL.get(st.status, st.status), st.detail),
                tags=(tag,),
            )
        summary = completion_summary(statuses)
        nxt = suggest_next_step(statuses)
        self.progress_summary_var.set(summary + (f"  |  建议下一步: {nxt}" if nxt else "  |  全部完成"))
        self.summary_var.set(self.progress_summary_var.get())
        self.status_var.set("进度已更新")
        if nxt:
            self.from_combo.set(nxt)
            self.to_combo.set(nxt)
            self.var_mode.set("step")
            for i, st in enumerate(PIPELINE_STEPS):
                if st[0] == nxt:
                    self.step_combo.current(i)
                    break
            self._toggle_mode()

    def _use_suggested_step(self):
        nxt = suggest_next_step(self.step_statuses)
        if not nxt:
            messagebox.showinfo("提示", "所有步骤均已完成")
            return
        self.var_mode.set("step")
        self.from_combo.set(nxt)
        self.to_combo.set(nxt)
        for i, st in enumerate(PIPELINE_STEPS):
            if st[0] == nxt:
                self.step_combo.current(i)
                break
        self._toggle_mode()
        self.notebook.select(self.tab_queue)
        messagebox.showinfo("已设置", f"已在「④ 任务队列」选中建议步骤 {nxt}，可加入队列或立即运行。")

    def _refresh_queue_view(self):
        for item in self.queue_tree.get_children():
            self.queue_tree.delete(item)
        for t in self.tasks:
            self.queue_tree.insert("", tk.END, iid=t.task_id, values=(t.task_id, t.label, t.status))

    def _enqueue_task(self):
        self._save_config_silent()
        task = add_task(self.settings)
        self.tasks = load_queue()
        self._refresh_queue_view()
        messagebox.showinfo("已加入队列", task.label)

    def _remove_selected_task(self):
        sel = self.queue_tree.selection()
        if not sel:
            return
        tid = sel[0]
        self.tasks = [t for t in self.tasks if t.task_id != tid]
        save_queue(self.tasks)
        self._refresh_queue_view()

    def _clear_finished_tasks(self):
        self.tasks = [t for t in self.tasks if t.status in ("pending", "running")]
        save_queue(self.tasks)
        self._refresh_queue_view()

    def _start_single_run(self):
        self._queue_mode = False
        self._current_task = None
        self._launch_run()

    def _start_queue_run(self):
        pending = [t for t in self.tasks if t.status == "pending"]
        if not pending:
            messagebox.showinfo("提示", "队列中没有待执行任务")
            return
        self._queue_mode = True
        self._launch_run()

    def _launch_run(self):
        if self._running:
            return
        try:
            cfg = self._server_config()
            self.runner._ensure_client(cfg)
            if self._queue_mode:
                task = next_pending(self.tasks)
                if task is None:
                    messagebox.showinfo("完成", "队列已全部执行完毕")
                    self._queue_mode = False
                    return
                task.status = "running"
                save_queue(self.tasks)
                self._refresh_queue_view()
                self._current_task = task
                cmd = SSHRunner.build_task_command(cfg, task)
                title = task.label
            else:
                s = self.settings
                cmd = SSHRunner.build_pipeline_command(
                    cfg, s["run_mode"],
                    step_id=s["step_id"], from_step=s["from_step"],
                    to_step=s["to_step"], phase=s["phase"],
                )
                title = "单次任务"
            self._save_config_silent()
            self._set_running(True)
            self.status_var.set("运行中…")
            self.notebook.select(self.tab_log)
            self._append_log(f"\n{'=' * 50}\n▶ {title}\n{cmd}\n{'=' * 50}\n")

            def on_log(chunk):
                self.log_queue.put(chunk)

            def on_done(code):
                self.log_queue.put(("done", code))

            self.runner.run_command_async(cmd, on_log, on_done)
        except Exception as exc:
            self._set_running(False)
            messagebox.showerror("启动失败", str(exc))

    def _stop_run(self):
        self.runner.stop()
        self._append_log("\n[用户停止]\n")
        if self._current_task:
            self._current_task.status = "cancelled"
            save_queue(self.tasks)
            self._refresh_queue_view()

    def _on_run_finished(self, exit_code: int):
        self._set_running(False)
        if self._current_task:
            self._current_task.status = "done" if exit_code == 0 else "failed"
            save_queue(self.tasks)
            self._refresh_queue_view()

        if exit_code == 0:
            self._append_log("\n✓ 任务成功\n")
            self.status_var.set("任务完成")
            self._refresh_progress()
            if self._queue_mode:
                self.after(800, self._start_queue_run)
            else:
                messagebox.showinfo("完成", "任务已在服务器上执行完成")
        else:
            self._append_log(f"\n✗ 退出码 {exit_code}\n")
            self.status_var.set("任务失败")
            if self._queue_mode:
                if self.var_stop_on_error.get():
                    self._queue_mode = False
                    messagebox.showwarning("队列暂停", f"任务失败 (exit {exit_code})，队列已停止")
                else:
                    self.after(800, self._start_queue_run)
            else:
                messagebox.showwarning("失败", f"退出码 {exit_code}")

    def _on_close(self):
        if self._running and not messagebox.askyesno("确认", "任务运行中，确定退出？"):
            return
        self.runner.stop()
        self.runner.disconnect()
        self.destroy()


def main():
    MetagenomicsDesktopApp().mainloop()


if __name__ == "__main__":
    main()
