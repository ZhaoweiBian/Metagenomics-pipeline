#!/bin/bash
# metaSPAdes 批量组装
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

activate_conda_env "${CONDA_ENV_MAIN}"

check_dir "$DEHOST_DIR" || exit 1
check_file "$SAMPLE_LIST" || exit 1
mkdir -p "$ASSEMBLY_CONTIG_DIR"

logfile="${ASSEMBLY_CONTIG_DIR}/spades_assembly.log"
echo "======== metaSPAdes 批量组装开始 ========" > "$logfile"
echo "开始时间: $(date)" >> "$logfile"

start_time=$(date +%s)
sample_count=0
fail_count=0

while IFS= read -r sample || [[ -n "$sample" ]]; do
    [[ -z "$sample" || "$sample" =~ ^# ]] && continue

    r1="${DEHOST_DIR}/${sample}_dehost_R1.fq.gz"
    r2="${DEHOST_DIR}/${sample}_dehost_R2.fq.gz"
    outdir="${ASSEMBLY_CONTIG_DIR}/${sample}_spades"

    if [[ ! -f "$r1" || ! -f "$r2" ]]; then
        log_warn "样本 $sample 缺少去宿主文件，跳过" | tee -a "$logfile"
        continue
    fi

    log_info "开始组装 $sample" | tee -a "$logfile"

    if spades.py --meta --only-assembler \
        -1 "$r1" -2 "$r2" \
        --threads "$THREADS_ASSEMBLY" --memory "$SPADES_MEMORY" \
        -o "$outdir" >> "$logfile" 2>&1; then
        log_info "样本 $sample 组装完成" | tee -a "$logfile"
        sample_count=$((sample_count + 1))
    else
        log_error "样本 $sample 组装失败" | tee -a "$logfile"
        fail_count=$((fail_count + 1))
    fi
done < "$SAMPLE_LIST"

runtime=$(format_runtime $(( $(date +%s) - start_time )))
log_info "所有样本组装任务完成" | tee -a "$logfile"

send_notification "metaSPAdes组装通知" \
"脚本: 3.1_contig_assembly.sh
服务器: $(hostname)
成功: $sample_count, 失败: $fail_count
耗时: $runtime
输出: $ASSEMBLY_CONTIG_DIR"
