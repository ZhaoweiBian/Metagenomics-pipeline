#!/usr/bin/env python3
"""汇总每个 MAG 的 KO 基因数，生成 MAG × KO 丰度矩阵。"""
import argparse
import glob
import os
import socket
import sys
from io import StringIO

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def load_annotations(annot_file):
    with open(annot_file) as f:
        lines = [line for line in f if not line.startswith("##")]
    annot = pd.read_csv(StringIO("".join(lines)), sep="\t", dtype=str)
    annot.columns = annot.columns.str.strip()
    annot.rename(columns=lambda x: x.replace("#", ""), inplace=True)
    return annot


def normalize_mag_name(name):
    for suffix in (".fa", ".fasta", ".fna"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def extract_mag_ko_counts(annot_dir):
    records = []
    annot_files = sorted(glob.glob(os.path.join(annot_dir, "*", "*.emapper.annotations")))
    if not annot_files:
        raise FileNotFoundError(f"未找到 MAG eggNOG 注释: {annot_dir}")

    for annot_file in annot_files:
        mag = normalize_mag_name(os.path.basename(annot_file).split(".emapper.annotations")[0])
        annot = load_annotations(annot_file)
        if "KEGG_ko" not in annot.columns:
            continue

        ko_col = annot["KEGG_ko"].dropna().astype(str).str.strip()
        ko_col = ko_col[ko_col != "-"]
        if ko_col.empty:
            continue

        ko_series = (
            ko_col.str.split(",")
            .explode()
            .str.strip()
            .loc[lambda s: s.str.match(r"ko:K\d+", na=False)]
            .str.replace("ko:", "", regex=False)
        )
        if ko_series.empty:
            continue

        counts = ko_series.value_counts()
        for ko, gene_count in counts.items():
            records.append({"MAG": mag, "KO": ko, "gene_count": int(gene_count)})

    if not records:
        raise ValueError("未从 MAG 注释中解析到有效 KO")

    long_df = pd.DataFrame(records)
    matrix = long_df.pivot_table(
        index="MAG", columns="KO", values="gene_count", aggfunc="sum", fill_value=0
    ).astype(int)
    presence = (matrix > 0).astype(int)
    return long_df, matrix, presence


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    mag_function = os.environ.get("MAG_FUNCTION_DIR", os.path.join(project_root, "MAG_function"))
    default_annot = os.environ.get("MAG_ANNOT_DIR", os.path.join(mag_function, "function_annotation"))
    default_out = os.environ.get("MAG_FUNCTION_MATRIX_DIR", os.path.join(mag_function, "function_matrix"))

    parser = argparse.ArgumentParser(description="Build MAG x KO abundance matrix")
    parser.add_argument("--annot-dir", default=default_annot, help="MAG eggNOG annotation root")
    parser.add_argument("--out-dir", default=default_out, help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    long_df, matrix, presence = extract_mag_ko_counts(args.annot_dir)

    long_path = os.path.join(args.out_dir, "mag_ko_gene_count_long.tsv")
    matrix_path = os.path.join(args.out_dir, "mag_ko_gene_count_matrix.tsv")
    presence_path = os.path.join(args.out_dir, "mag_ko_presence_matrix.tsv")

    long_df.to_csv(long_path, sep="\t", index=False)
    matrix.to_csv(matrix_path, sep="\t")
    presence.to_csv(presence_path, sep="\t")

    print("========== MAG × KO 丰度矩阵 ==========")
    print(f"MAG 数: {matrix.shape[0]}")
    print(f"KO 数: {matrix.shape[1]}")
    print(f"输出目录: {args.out_dir}")
    print(f"- {long_path}")
    print(f"- {matrix_path}")
    print(f"- {presence_path}")

    send_notification(
        "MAG KO矩阵通知",
        f"脚本: 7.3_MAG_KO_abundance_matrix.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"MAG数: {matrix.shape[0]}, KO数: {matrix.shape[1]}\n"
        f"输出: {args.out_dir}",
    )


if __name__ == "__main__":
    main()
