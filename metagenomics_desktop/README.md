# 宏基因组 Pipeline 桌面客户端

图形化连接远程 Linux 服务器，完成样本上传、进度查看、任务队列与日志监控。  
**无需命令行基础**，按标签页顺序操作即可。

## 安装与启动

```bash
cd metagenomics_desktop
pip install -r requirements.txt
python main.py
```

Windows 可双击 `start.bat` 启动。

## 推荐操作流程（5 步）

```
① 连接  →  ② 项目准备  →  ③ 运行进度  →  ④ 任务队列  →  ⑤ 日志
```

| 标签页 | 做什么 |
|--------|--------|
| **① 连接** | 填服务器 IP、用户名、SSH 密钥；脚本目录与项目路径；测试连接 |
| **② 项目准备** | 上传 `samplelist`；检查磁盘空间；预览样本列表 |
| **③ 运行进度** | 刷新各步骤完成状态（绿=已完成）；获取「建议下一步」 |
| **④ 任务队列** | 添加阶段/单步/区间任务；顺序执行；支持断点续跑 |
| **⑤ 日志** | 实时查看服务器运行输出 |

## 功能说明

### 上传样本列表

1. 在「② 项目准备」点击「选择…」选本地 `samplelist` 文件  
2. 点击「上传到服务器」→ 保存为 `{PROJECT_ROOT}/samplelist`  
3. 点击「刷新」预览服务器上的样本名与数量  

### 检查磁盘空间

点击「检查磁盘空间」，显示项目目录所在分区可用空间。  
组装/Binning 阶段建议 **>200GB** 可用。

### 断点续跑进度面板

「③ 运行进度」通过扫描服务器输出文件判断每步状态：

- **已完成**：对应结果文件/目录已存在  
- **未开始**：尚未检测到输出  

点击 **刷新进度** 后，顶部会显示 `已完成步数/总步数` 和 **建议下一步**。  
点击 **从建议步骤继续** 会自动跳到「④ 任务队列」并选好该步骤。

### 任务队列

- **加入队列**：将当前选中的阶段/步骤加入待执行列表  
- **开始执行队列**：按顺序逐个运行；上一步成功才自动执行下一步  
- **立即运行**：不排队，直接执行当前选中任务  
- 队列保存在 `~/.metagenomics_desktop/task_queue.json`，重启软件不丢失  

适合一次性添加多个阶段，例如：

1. `qc`
2. `assembly`
3. `binning`
4. `mag_function`

### 邮件通知

在「① 连接」勾选「任务完成后发送邮件通知」，等同设置 `ENABLE_EMAIL=true`。

## 打包为 Windows .exe

在 **Windows 电脑**上：

```bat
cd metagenomics_desktop
build_exe.bat
```

完成后得到 `dist\MetagenomicsPipeline.exe`，可复制给其他用户直接双击运行（无需安装 Python）。

手动打包：

```bat
pip install paramiko pyinstaller
pyinstaller --clean MetagenomicsPipeline.spec
```

## 服务器端要求

- 已部署本仓库 `script/` 目录（含 `run_pipeline.sh`）  
- `metagenomics_desktop/remote_check_status.sh` 用于进度扫描（随仓库一起部署）  
- conda 环境：`metagenomics`、`checkm2`、`gtdbtk-2.5.2`、`eggnog_env`、`dbcan_env`（cazyme）、`rgi_env`（card）  
- 项目目录下有测序数据与 `samplelist`  
- 数据库：`/data1/resource/dbcan_db`、`/data1/resource/card`（cazyme/card）  

## 配置保存位置

| 文件 | 内容 |
|------|------|
| `~/.metagenomics_desktop/settings.json` | 连接与路径配置 |
| `~/.metagenomics_desktop/task_queue.json` | 任务队列 |

## 架构

```
本地 GUI (tkinter)
    │ SSH / SFTP
    ▼
远程服务器
    ├── run_pipeline.sh      # 执行分析
    └── remote_check_status.sh  # 进度扫描
```

## 常见问题

**Q: 进度显示不准确？**  
点击「刷新进度」；确认 `PROJECT_ROOT` 路径正确。

**Q: 长任务会断开吗？**  
SSH 连接在任务运行期间保持；请勿让电脑休眠。极长任务建议在服务器 `screen` 中手动跑，GUI 适合阶段化队列。

**Q: 私钥权限？**  
Linux/macOS: `chmod 600 ~/.ssh/id_rsa`
