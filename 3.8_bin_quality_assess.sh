#!/bin/bash
# CheckM2 批量 MAG 质量评估
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# CheckM2 在独立 conda 环境中运行
activate_conda_env "${CONDA_ENV_CHECKM2}"

start_time=$(date +%s)
sample_count=0
failed_samples=()

cd "$ASSEMBLY_CONTIG_DIR" || exit 1

for dir in *_spades; do
    [[ -d "$dir" ]] || continue
    sample=${dir%_spades}

    bin_count=$(find "${dir}/binning" -name '*.fa' 2>/dev/null | wc -l)
    mkdir -p "${dir}/checkM2_result"

    if [[ "$bin_count" -eq 0 ]]; then
        log_warn "$sample binning 为空，跳过 CheckM2"
        touch "${dir}/checkM2_result/README_empty.txt"
        sample_count=$((sample_count + 1))
        continue
    fi

    log_info "CheckM2: $sample"
    (cd "$dir" && checkm2 predict \
        --threads "$THREADS_CHECKM2" -x fa \
        --input ./binning \
        --output-directory ./checkM2_result \
        --database_path "$CHECKM2_DB") \
        || failed_samples+=("$sample")

    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
msg="CheckM2完成. 样本: $sample_count, 耗时: $runtime"
[[ ${#failed_samples[@]} -gt 0 ]] && msg+="\n失败: ${failed_samples[*]}"

# 恢复主分析环境，供后续步骤使用
activate_conda_env "${CONDA_ENV_MAIN}"

send_notification "CheckM2任务通知" "$msg"
