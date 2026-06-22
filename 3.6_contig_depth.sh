#!/bin/bash
# 批量计算 contig depth (MetaBAT2 输入)
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
    bam="${ASSEMBLY_CONTIG_DIR}/${dir}/${sample}.sort.bam"

    if [[ ! -f "$bam" ]]; then
        log_warn "BAM 不存在: $bam, 跳过"
        continue
    fi

    log_info "Depth calculation: $sample"
    (cd "$dir" && jgi_summarize_bam_contig_depths \
        --outputDepth "${sample}.depth.txt" \
        "${sample}.sort.bam") || status=1

    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "Depth finished. Samples: $sample_count, Time: $runtime"

send_notification "Contig Depth任务通知" \
"脚本: 3.6_contig_depth.sh
服务器: $(hostname)
状态: $([ $status -eq 0 ] && echo 成功 || echo 失败)
样本数: $sample_count
耗时: $runtime"

exit $status
