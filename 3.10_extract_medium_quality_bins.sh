#!/bin/bash
# 筛选中等质量 MAG (MIMAG: Completeness≥50, Contamination≤10) 并汇总
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

start_time=$(date +%s)
sample_count=0
total_mag=0
failed_samples=()

mkdir -p "$MQ_MAG_DIR"
quality_tsv="${ASSEMBLY_CONTIG_DIR}/all_medium_quality_bins.tsv"
echo -e "Sample\tName\tCompleteness\tContamination\tGenome_Size\tTotal_Contigs\tContig_N50\tGC_Content" > "$quality_tsv"

cd "$ASSEMBLY_CONTIG_DIR" || exit 1

for dir in *_spades; do
    [[ -d "$dir" ]] || continue
    sample=${dir%_spades}

    checkm2_dir="${dir}/checkM2_result"
    bin_dir="${dir}/binning"
    output_dir="${dir}/medium_quality_bins"

    if [[ ! -f "${checkm2_dir}/quality_report.tsv" ]]; then
        log_warn "无 quality_report.tsv: $sample"
        failed_samples+=("$sample")
        continue
    fi

    mkdir -p "$output_dir"

    awk -F'\t' -v s="$sample" -v comp="$MAG_MQ_COMPLETENESS" -v con="$MAG_MQ_CONTAMINATION" \
        'NR>1 && $2>=comp && $3<=con {print s"\t"$1".fa\t"$2"\t"$3"\t"$9"\t"$12"\t"$7"\t"$10}' \
        "${checkm2_dir}/quality_report.tsv" >> "$quality_tsv"

    awk -F'\t' -v comp="$MAG_MQ_COMPLETENESS" -v con="$MAG_MQ_CONTAMINATION" \
        'NR>1 && $2>=comp && $3<=con {print $1}' \
        "${checkm2_dir}/quality_report.tsv" > "${checkm2_dir}/medium_quality_bins.txt"

    bin_number=0
    while IFS= read -r bin || [[ -n "$bin" ]]; do
        [[ -z "$bin" ]] && continue
        src="${bin_dir}/${bin}.fa"
        if [[ -f "$src" ]]; then
            cp "$src" "$output_dir/"
            cp "$src" "$MQ_MAG_DIR/"
            total_mag=$((total_mag + 1))
            bin_number=$((bin_number + 1))
        else
            log_warn "未找到 bin: $src"
        fi
    done < "${checkm2_dir}/medium_quality_bins.txt"

    log_info "$sample 中等质量MAG: $bin_number"
    sample_count=$((sample_count + 1))
done

runtime=$(format_runtime $(( $(date +%s) - start_time )))
send_notification "中等质量MAG筛选通知" \
"中等质量MAG筛选完成
标准: Completeness≥${MAG_MQ_COMPLETENESS}, Contamination≤${MAG_MQ_CONTAMINATION}
样本: $sample_count, 中等质量MAG: $total_mag
耗时: $runtime
输出: $MQ_MAG_DIR"
