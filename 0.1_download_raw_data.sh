#!/bin/bash
# 批量下载 linklist.txt 中所有文件（自动去掉 ^M 回车符）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

DOWNLOAD_DIR="$RAW_DATA_DIR"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR" || exit 1

if [[ ! -f "$LINKLIST" ]]; then
    if compgen -G "${RAW_DATA_DIR}/*_1.fq.gz" > /dev/null; then
        log_info "未找到 linklist.txt，${RAW_DATA_DIR} 已有原始测序数据，跳过下载 (0.1)"
        exit 0
    fi
    check_file "$LINKLIST" || exit 1
fi

start_time=$(date +%s)
file_count=0

# 去掉 Windows 回车符
sed -i 's/\r$//' "$LINKLIST"

while IFS= read -r url || [[ -n "$url" ]]; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    filename=$(basename "${url%%\?*}")
    log_info "Downloading $filename ..."
    wget -c "$url" -O "$filename"
    file_count=$((file_count + 1))
done < "$LINKLIST"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "All downloads completed."

send_notification "原始数据下载通知" \
"脚本: 0.1_download_raw_data.sh
服务器: $(hostname)
文件数: $file_count
耗时: $runtime
输出: $DOWNLOAD_DIR"
