#!/bin/bash
# Contig 预处理: 重命名 + 添加样本前缀
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

log_info "Contig preprocessing start"

start_time=$(date +%s)
sample_count=0

for dir in "$ASSEMBLY_CONTIG_DIR"/*_spades; do
    [[ -d "$dir" ]] || continue
    sample=$(basename "$dir" _spades)

    input_fasta="${dir}/contigs.fasta"
    renamed_fasta="${dir}/${sample}_contigs.fasta"
    tmp_fasta="${dir}/${sample}_contigs.tmp.fasta"

    if [[ ! -f "$input_fasta" ]]; then
        log_warn "$input_fasta not found, skip"
        continue
    fi

    mv "$input_fasta" "$renamed_fasta"

    awk -v sample="$sample" '
    /^>/ { sub(/^>/, ""); print ">" sample "_" $0; next }
    { print }
    ' "$renamed_fasta" > "$tmp_fasta"

    mv "$tmp_fasta" "$renamed_fasta"
    log_info "Finished: $sample"
    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "All samples processed"

send_notification "Contig预处理通知" \
"脚本: 3.2_preprocess_contigs.sh
服务器: $(hostname)
样本数: $sample_count
耗时: $runtime
输出: $ASSEMBLY_CONTIG_DIR"
