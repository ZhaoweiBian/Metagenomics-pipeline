#!/bin/bash
# Kraken2 + Bracken 物种注释与丰度校正
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

mkdir -p "$KRAKEN2_DIR" "$BRACKEN_DIR" "$LOG_DIR"
for level in Species Genus Family Order Class Phylum; do
    mkdir -p "${BRACKEN_DIR}/${level}"
done

check_file "$SAMPLE_LIST" || exit 1

log_info "Kraken2 + Bracken started"
start=$(date +%s)
sample_count=0

while IFS= read -r sample || [[ -n "$sample" ]]; do
    [[ -z "$sample" || "$sample" =~ ^# ]] && continue
    log_info "Processing sample: $sample"

    r1="${DEHOST_DIR}/${sample}_dehost_R1.fq.gz"
    r2="${DEHOST_DIR}/${sample}_dehost_R2.fq.gz"
    check_file "$r1" || exit 1
    check_file "$r2" || exit 1

    kraken_report="${KRAKEN2_DIR}/${sample}.kraken.report"
    kraken_out="${KRAKEN2_DIR}/${sample}.kraken.out"
    kraken_log="${LOG_DIR}/${sample}_kraken.log"

    kraken2 \
        --db "$KRAKEN2_DB" \
        --threads "$THREADS_KRAKEN" \
        --paired "$r1" "$r2" \
        --report "$kraken_report" \
        --output "$kraken_out" \
        --use-names \
        > "$kraken_log" 2>&1

    for level in S G F O C P; do
        case "$level" in
            S) level_dir="Species" ;;
            G) level_dir="Genus" ;;
            F) level_dir="Family" ;;
            O) level_dir="Order" ;;
            C) level_dir="Class" ;;
            P) level_dir="Phylum" ;;
        esac

        bracken_out="${BRACKEN_DIR}/${level_dir}/${sample}.${level}.bracken"
        bracken_log="${LOG_DIR}/${sample}_${level_dir}_bracken.log"

        bracken \
            -d "$KRAKEN2_DB" \
            -i "$kraken_report" \
            -o "$bracken_out" \
            -l "$level" \
            -r "$BRACKEN_READLEN" \
            > "$bracken_log" 2>&1
    done

    log_info "Bracken completed for $sample"
    sample_count=$((sample_count + 1))
done < "$SAMPLE_LIST"

runtime=$(format_runtime $(( $(date +%s) - start )))
log_info "All samples finished. Elapsed: $runtime"

send_notification "Kraken2+Bracken通知" \
"脚本: 2.1_kraken_bracken.sh
服务器: $(hostname)
样本数: $sample_count
耗时: $runtime
输出: $KRAKEN2_DIR, $BRACKEN_DIR"
