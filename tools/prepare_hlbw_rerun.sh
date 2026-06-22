#!/usr/bin/env bash
# =============================================================================
# hlbw 重跑准备：备份原始测序 → 对调错误样本名 → 清空旧分析结果
#
# 用法:
#   ./tools/prepare_hlbw_rerun.sh backup-rename    # 仅备份 + 重命名 raw
#   ./tools/prepare_hlbw_rerun.sh clear-results    # 仅清空 PROJECT_ROOT 下游结果
#   ./tools/prepare_hlbw_rerun.sh all              # 先 backup-rename 再 clear-results
#   ./tools/prepare_hlbw_rerun.sh status           # 查看当前状态
# =============================================================================
set -euo pipefail

RAW_DATA_DIR="${RAW_DATA_DIR:-/data1/bianzw/project/data_raw}"
RAW_BACKUP_DIR="${RAW_BACKUP_DIR:-/data1/bianzw/project/data_raw_backup_original_names}"
PROJECT_ROOT="${PROJECT_ROOT:-/data1/bianzw/hlbw}"
SAMPLE_LIST_KEEP="${SAMPLE_LIST_KEEP:-${PROJECT_ROOT}/samplelist.txt}"

SWAP_PAIRS=("A31:A32" "A61:A62")

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { log "ERROR: $*"; exit 1; }

swap_pair_in_dir() {
    local dir="$1"
    local a="$2"
    local b="$3"
    local end tmp f1 f2

    for end in 1 2; do
        f1="${dir}/${a}_${end}.fq.gz"
        f2="${dir}/${b}_${end}.fq.gz"
        [[ -f "$f1" ]] || die "缺少文件: $f1"
        [[ -f "$f2" ]] || die "缺少文件: $f2"
        tmp="${dir}/${a}_${end}.fq.gz.swaptmp"
        mv "$f1" "$tmp"
        mv "$f2" "$f1"
        mv "$tmp" "$f2"
        log "  已对调: $(basename "$f1") <-> $(basename "$f2")"
    done
}

cmd_backup_rename() {
    [[ -d "$RAW_DATA_DIR" ]] || die "原始数据目录不存在: $RAW_DATA_DIR"

    if [[ -d "$RAW_BACKUP_DIR" ]] && [[ -n "$(ls -A "$RAW_BACKUP_DIR" 2>/dev/null)" ]]; then
        log "备份目录已存在且非空，跳过复制: $RAW_BACKUP_DIR"
    else
        log "备份原始测序 → $RAW_BACKUP_DIR"
        mkdir -p "$(dirname "$RAW_BACKUP_DIR")"
        rsync -a --info=progress2 "$RAW_DATA_DIR/" "$RAW_BACKUP_DIR/"
        log "备份完成"
    fi

    log "在 $RAW_DATA_DIR 中对调样本名（A31↔A32，A61↔A62）"
    local pair a b
    for pair in "${SWAP_PAIRS[@]}"; do
        a="${pair%%:*}"
        b="${pair##*:}"
        log "交换 $a <-> $b"
        swap_pair_in_dir "$RAW_DATA_DIR" "$a" "$b"
    done
}

cmd_clear_results() {
    [[ -d "$PROJECT_ROOT" ]] || die "项目目录不存在: $PROJECT_ROOT"

    local -a remove_dirs=(
        assembly bracken bracken_merged contig_function coverm dehost
        gtdbtk gtdbtk_mq kraken2 logs MAG_function qc raw
    )

    log "将清空 $PROJECT_ROOT 下分析结果，保留: $(basename "$SAMPLE_LIST_KEEP")"
    local d
    for d in "${remove_dirs[@]}"; do
        if [[ -e "${PROJECT_ROOT}/${d}" ]]; then
            log "  删除: ${PROJECT_ROOT}/${d}"
            rm -rf "${PROJECT_ROOT}/${d}"
        fi
    done
}

cmd_status() {
    echo "RAW_DATA_DIR:   $RAW_DATA_DIR"
    echo "RAW_BACKUP_DIR: $RAW_BACKUP_DIR"
    echo "PROJECT_ROOT:   $PROJECT_ROOT"
    echo ""
    ls -lh "$RAW_DATA_DIR"/*_{1,2}.fq.gz 2>/dev/null | awk '{print $9, $5}' | head -24 || echo "  (无 raw 文件)"
    echo ""
    for d in assembly qc dehost contig_function MAG_function gtdbtk gtdbtk_mq coverm; do
        if [[ -d "${PROJECT_ROOT}/${d}" ]]; then
            echo "  ${d}: $(du -sh "${PROJECT_ROOT}/${d}" | cut -f1)"
        else
            echo "  ${d}: (无)"
        fi
    done
}

usage() {
    cat <<EOF
用法: $0 {backup-rename|clear-results|all|status}
EOF
}

main() {
    case "${1:-}" in
        backup-rename) cmd_backup_rename ;;
        clear-results) cmd_clear_results ;;
        all) cmd_backup_rename; cmd_clear_results ;;
        status) cmd_status ;;
        -h|--help|"") usage ;;
        *) die "未知子命令: $1" ;;
    esac
}

main "$@"
