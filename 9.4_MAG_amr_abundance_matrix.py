#!/usr/bin/env python3
"""汇总每个 dRep MAG 的 CARD ARO 基因数，生成 MAG × ARO 矩阵。"""
import argparse
import glob
import os
import socket
import sys

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def normalize_mag_name(name):
    for suffix in ("_card", ".fa", ".fasta", ".fna"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
    return name


def load_rgi_hits(path):
    hits = pd.read_csv(path, sep="\t", dtype=str)
    hits.columns = hits.columns.str.strip()
    aro_col = "Best_Hit_ARO" if "Best_Hit_ARO" in hits.columns else "ARO"
    hits = hits.dropna(subset=[aro_col])
    hits = hits[hits[aro_col].astype(str).str.strip() != ""]
    return hits[aro_col].astype(str).str.strip()


def extract_mag_amr_counts(annot_dir):
    records = []
    result_files = sorted(glob.glob(os.path.join(annot_dir, "*", "*_card.txt")))
    if not result_files:
        raise FileNotFoundError(f"未找到 dRep MAG RGI 结果: {annot_dir}")

    for result_file in result_files:
        mag = normalize_mag_name(os.path.basename(os.path.dirname(result_file)))
        aro_series = load_rgi_hits(result_file)
        if aro_series.empty:
            continue
        counts = aro_series.value_counts()
        for aro, gene_count in counts.items():
            records.append({"MAG": mag, "ARO": aro, "gene_count": int(gene_count)})

    if not records:
        raise ValueError("未从 dRep MAG RGI 注释中解析到 ARO")

    long_df = pd.DataFrame(records)
    matrix = long_df.pivot_table(
        index="MAG", columns="ARO", values="gene_count", aggfunc="sum", fill_value=0
    ).astype(int)
    presence = (matrix > 0).astype(int)
    return long_df, matrix, presence


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    mag_function = os.environ.get("MAG_FUNCTION_DIR", os.path.join(project_root, "MAG_function"))
    default_annot = os.environ.get(
        "MAG_CARD_DIR", os.path.join(mag_function, "card_annotation")
    )
    default_out = os.environ.get(
        "MAG_FUNCTION_MATRIX_DIR", os.path.join(mag_function, "function_matrix")
    )

    parser = argparse.ArgumentParser(description="Build dRep MAG x AMR abundance matrix")
    parser.add_argument("--annot-dir", default=default_annot)
    parser.add_argument("--out-dir", default=default_out)
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    long_df, matrix, presence = extract_mag_amr_counts(args.annot_dir)

    long_path = os.path.join(args.out_dir, "mag_amr_gene_count_long.tsv")
    matrix_path = os.path.join(args.out_dir, "mag_amr_gene_count_matrix.tsv")
    presence_path = os.path.join(args.out_dir, "mag_amr_presence_matrix.tsv")

    long_df.to_csv(long_path, sep="\t", index=False)
    matrix.to_csv(matrix_path, sep="\t")
    presence.to_csv(presence_path, sep="\t")

    print("========== dRep MAG × AMR 丰度矩阵 ==========")
    print(f"MAG 数: {matrix.shape[0]}")
    print(f"ARO 数: {matrix.shape[1]}")
    print(f"输出目录: {args.out_dir}")

    send_notification(
        "dRep MAG AMR矩阵通知",
        f"脚本: 9.4_MAG_amr_abundance_matrix.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"MAG数: {matrix.shape[0]}, ARO数: {matrix.shape[1]}\n"
        f"输出: {args.out_dir}",
    )


if __name__ == "__main__":
    main()
