#!/bin/bash
# MetaBAT2 批量 binning
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
sample_count=0
empty_bins=()
failed_samples=()

cd "$ASSEMBLY_CONTIG_DIR" || exit 1

for dir in *_spades; do
    [[ -d "$dir" ]] || continue
    sample=${dir%_spades}

    contig="${dir}/${sample}_contigs.fasta"
    depth="${dir}/${sample}.depth.txt"

    if [[ ! -f "$contig" || ! -f "$depth" ]]; then
        log_warn "缺少输入文件: $sample, 跳过"
        continue
    fi

    log_info "Binning: $sample"
    (cd "$dir" && mkdir -p binning && \
        metabat2 -t "$THREADS_BINNING" \
            -i "${sample}_contigs.fasta" \
            -a "${sample}.depth.txt" \
            -o "binning/${sample}_bin" \
            --minContig "$MIN_CONTIG_BINNING" -v) \
        || { failed_samples+=("$sample"); continue; }

    # MetaBAT2 输出 binning/${sample}_bin.N.fa
    bin_count=$(find "${dir}/binning" -name '*.fa' 2>/dev/null | wc -l)
    if [[ "$bin_count" -eq 0 ]]; then
        log_warn "No bins: $sample"
        empty_bins+=("$sample")
    fi

    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
msg="Binning完成. 样本: $sample_count, 耗时: $runtime"
[[ ${#failed_samples[@]} -gt 0 ]] && msg+="\n失败: ${failed_samples[*]}"
[[ ${#empty_bins[@]} -gt 0 ]] && msg+="\n空bin: ${empty_bins[*]}"
log_info "$msg"
send_notification "MetaBAT2 Binning通知" "$msg"
