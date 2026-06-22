@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================
echo  宏基因组 Pipeline 桌面端 - Windows 打包
echo ========================================

python --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Python，请先安装 Python 3.9+
    pause
    exit /b 1
)

echo [1/3] 安装依赖...
pip install -r requirements.txt pyinstaller
if errorlevel 1 exit /b 1

echo [2/3] 打包 exe（约 1-3 分钟）...
pyinstaller --clean --noconfirm MetagenomicsPipeline.spec
if errorlevel 1 exit /b 1

echo [3/3] 完成
echo.
echo 可执行文件: dist\MetagenomicsPipeline.exe
echo 可将 dist\MetagenomicsPipeline.exe 复制到任意 Windows 电脑运行
echo.
pause
