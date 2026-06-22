#!/usr/bin/env bash
# Linux 下打包（生成 Linux 可执行文件；Windows exe 请在 Windows 上运行 build_exe.bat）
set -euo pipefail
cd "$(dirname "$0")"
echo "安装依赖..."
pip install -r requirements.txt pyinstaller
echo "打包..."
pyinstaller --clean --noconfirm MetagenomicsPipeline.spec
echo "完成: dist/MetagenomicsPipeline"
