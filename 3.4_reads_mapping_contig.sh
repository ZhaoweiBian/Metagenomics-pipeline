#!/bin/bash
# 批量将去宿主 reads 比对到各样本 contigs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

cd "$ASSEMBLY_CONTIG_DIR" || exit 1

start_time=$(date +%s)
sample_count=0
failed=0

for dir in *_spades; do
    [[ -d "$dir" ]] || continue
    sample=${dir%_spades}

    r1="${DEHOST_DIR}/${sample}_dehost_R1.fq.gz"
    r2="${DEHOST_DIR}/${sample}_dehost_R2.fq.gz"

    if [[ ! -f "$r1" || ! -f "$r2" ]]; then
        log_warn "缺失 reads: $sample, 跳过"
        continue
    fi

    log_info "Mapping sample: $sample"
    if ! (cd "$dir" && bowtie2 \
        -1 "$r1" -2 "$r2" \
        -p "$THREADS_MAPPING" \
        -x "${sample}_contigs.fasta" \
        -S "${sample}.sam"); then
        log_error "比对失败: $sample"
        failed=$((failed + 1))
        continue
    fi
    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
if [[ $failed -gt 0 ]]; then
    log_error "Mapping 失败样本数: $failed"
    exit 1
fi
log_info "All samples mapping finished"

send_notification "Reads比对通知" \
"脚本: 3.4_reads_mapping_contig.sh
服务器: $(hostname)
样本数: $sample_count
耗时: $runtime
输出: $ASSEMBLY_CONTIG_DIR"
