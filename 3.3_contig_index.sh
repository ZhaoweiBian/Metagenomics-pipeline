#!/bin/bash
# 批量为每个样本 contigs 构建 Bowtie2 索引
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

check_dir "$ASSEMBLY_CONTIG_DIR" || exit 1

logfile="${ASSEMBLY_CONTIG_DIR}/bowtie2_index.log"
echo "======== Bowtie2 索引构建开始 ========" > "$logfile"

start_time=$(date +%s)
sample_count=0
fail_count=0

for dir in "$ASSEMBLY_CONTIG_DIR"/*_spades; do
    [[ -d "$dir" ]] || continue
    sample=$(basename "$dir" _spades)
    contig_file="${dir}/${sample}_contigs.fasta"

    if [[ ! -f "$contig_file" ]]; then
        log_warn "样本 $sample contig 不存在，跳过" | tee -a "$logfile"
        continue
    fi

    log_info "建索引: $sample" | tee -a "$logfile"
    if (cd "$dir" && bowtie2-build -f "${sample}_contigs.fasta" "${sample}_contigs.fasta" \
        --threads "$THREADS_INDEX" >> "$logfile" 2>&1); then
        log_info "索引完成: $sample" | tee -a "$logfile"
        sample_count=$((sample_count + 1))
    else
        log_error "索引失败: $sample" | tee -a "$logfile"
        fail_count=$((fail_count + 1))
    fi
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "Bowtie2 索引任务完成" | tee -a "$logfile"

send_notification "Bowtie2索引通知" \
"脚本: 3.3_contig_index.sh
服务器: $(hostname)
成功: $sample_count, 失败: $fail_count
耗时: $runtime
输出: $ASSEMBLY_CONTIG_DIR"
