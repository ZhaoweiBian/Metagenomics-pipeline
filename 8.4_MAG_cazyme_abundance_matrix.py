#!/usr/bin/env python3
"""汇总每个 dRep MAG 的 CAZyme family 基因数，生成 MAG × family 矩阵。"""
import argparse
import glob
import os
import re
import socket
import sys

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification

FAMILY_RE = re.compile(r"^([A-Za-z0-9_-]+)")


def parse_cazyme_family(row):
    for col in ("Recommend Results", "dbCAN_hmm", "DIAMOND", "dbCAN_sub"):
        val = str(row.get(col, "-")).strip()
        if not val or val == "-":
            continue
        m = FAMILY_RE.match(val.split("(")[0].strip())
        if m:
            return m.group(1)
    return None


def normalize_mag_name(name):
    for suffix in (".fa", ".fasta", ".fna"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def extract_mag_cazyme_counts(annot_dir):
    records = []
    overview_files = sorted(glob.glob(os.path.join(annot_dir, "*", "overview.tsv")))
    if not overview_files:
        raise FileNotFoundError(f"未找到 dRep MAG dbCAN overview: {annot_dir}")

    for overview_file in overview_files:
        mag = normalize_mag_name(os.path.basename(os.path.dirname(overview_file)))
        overview = pd.read_csv(overview_file, sep="\t", dtype=str)
        overview.columns = overview.columns.str.strip()
        overview["CAZyme_family"] = overview.apply(parse_cazyme_family, axis=1)
        families = overview["CAZyme_family"].dropna()
        if families.empty:
            continue
        counts = families.value_counts()
        for family, gene_count in counts.items():
            records.append({"MAG": mag, "CAZyme_family": family, "gene_count": int(gene_count)})

    if not records:
        raise ValueError("未从 dRep MAG dbCAN 注释中解析到 CAZyme family")

    long_df = pd.DataFrame(records)
    matrix = long_df.pivot_table(
        index="MAG",
        columns="CAZyme_family",
        values="gene_count",
        aggfunc="sum",
        fill_value=0,
    ).astype(int)
    presence = (matrix > 0).astype(int)
    return long_df, matrix, presence


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    mag_function = os.environ.get("MAG_FUNCTION_DIR", os.path.join(project_root, "MAG_function"))
    default_annot = os.environ.get(
        "MAG_DBCAN_DIR", os.path.join(mag_function, "dbcan_annotation")
    )
    default_out = os.environ.get(
        "MAG_FUNCTION_MATRIX_DIR", os.path.join(mag_function, "function_matrix")
    )

    parser = argparse.ArgumentParser(description="Build dRep MAG x CAZyme abundance matrix")
    parser.add_argument("--annot-dir", default=default_annot)
    parser.add_argument("--out-dir", default=default_out)
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    long_df, matrix, presence = extract_mag_cazyme_counts(args.annot_dir)

    long_path = os.path.join(args.out_dir, "mag_cazyme_gene_count_long.tsv")
    matrix_path = os.path.join(args.out_dir, "mag_cazyme_gene_count_matrix.tsv")
    presence_path = os.path.join(args.out_dir, "mag_cazyme_presence_matrix.tsv")

    long_df.to_csv(long_path, sep="\t", index=False)
    matrix.to_csv(matrix_path, sep="\t")
    presence.to_csv(presence_path, sep="\t")

    print("========== dRep MAG × CAZyme 丰度矩阵 ==========")
    print(f"MAG 数: {matrix.shape[0]}")
    print(f"CAZyme family 数: {matrix.shape[1]}")
    print(f"输出目录: {args.out_dir}")

    send_notification(
        "dRep MAG CAZyme矩阵通知",
        f"脚本: 8.4_MAG_cazyme_abundance_matrix.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"MAG数: {matrix.shape[0]}, CAZyme family数: {matrix.shape[1]}\n"
        f"输出: {args.out_dir}",
    )


if __name__ == "__main__":
    main()
