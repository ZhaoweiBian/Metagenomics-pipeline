#!/bin/bash
# SAM 转 sorted BAM 并清理中间文件
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
sample_count=0
status=0

cd "$ASSEMBLY_CONTIG_DIR" || exit 1

for dir in *_spades; do
    [[ -d "$dir" ]] || continue
    sample=${dir%_spades}

    sam_file="${ASSEMBLY_CONTIG_DIR}/${dir}/${sample}.sam"
    if [[ ! -f "$sam_file" ]]; then
        log_warn "SAM 不存在: $sam_file, 跳过"
        continue
    fi

    log_info "Processing sample: $sample"
    (cd "$dir" && \
        samtools view -bS -@ "$THREADS_SAMTOOLS" "${sample}.sam" -o "${sample}.bam" && \
        samtools sort -@ "$THREADS_SAMTOOLS" -l 6 -O BAM "${sample}.bam" -o "${sample}.sort.bam" && \
        rm -f "${sample}.bam" "${sample}.sam") || status=1

    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "SAM to BAM finished. Samples: $sample_count, Time: $runtime"

send_notification "SAM转BAM任务通知" \
"脚本: 3.5_sam_to_bam.sh
服务器: $(hostname)
状态: $([ $status -eq 0 ] && echo 成功 || echo 失败)
样本数: $sample_count
耗时: $runtime"

exit $status
