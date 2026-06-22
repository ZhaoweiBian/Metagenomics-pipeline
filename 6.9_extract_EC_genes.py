#!/usr/bin/env python3
"""从 gene_with_full_annotation_TPM.tsv 按 EC 精确提取基因行。"""
import argparse
import os
import re
import socket
import sys

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib.notify import send_notification


def ec_pattern(ec):
    escaped = re.escape(ec)
    return rf"(^|[;|,]){escaped}($|[;|,])"


def ec_filename(ec):
    return f"EC_{ec.replace('.', '_')}_genes.tsv"


def extract_by_ec(df, ec):
    if "EC" not in df.columns:
        raise ValueError("输入表缺少 EC 列")
    pat = ec_pattern(ec)
    return df[df["EC"].str.contains(pat, regex=True, na=False)]


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    gene_quant = os.path.join(project_root, "contig_function/gene_quant")
    default_matrix = os.environ.get(
        "FUNCTION_MATRIX_DIR", os.path.join(gene_quant, "function_matrix")
    )
    default_ec = os.environ.get("EXTRACT_EC", "1.1.1.27")

    parser = argparse.ArgumentParser(description="Extract genes by EC from full annotation TPM table")
    parser.add_argument(
        "--input",
        default=os.path.join(default_matrix, "gene_with_full_annotation_TPM.tsv"),
        help="6.8 输出的基因注释×丰度表",
    )
    parser.add_argument(
        "--ec",
        default=default_ec,
        help="目标 EC 号，多个用逗号分隔（默认从 EXTRACT_EC 读取）",
    )
    parser.add_argument("--out-dir", default=default_matrix, help="输出目录")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    ec_list = [e.strip() for e in args.ec.split(",") if e.strip()]
    if not ec_list:
        raise SystemExit("未指定 EC")

    print(f"读取: {args.input}")
    df = pd.read_csv(args.input, sep="\t", dtype=str, low_memory=False)

    outputs = []
    for ec in ec_list:
        hit = extract_by_ec(df, ec)
        out_path = os.path.join(args.out_dir, ec_filename(ec))
        hit.to_csv(out_path, sep="\t", index=False)
        print(f"EC {ec}: {len(hit)} 行 → {out_path}")
        outputs.append(f"{ec}: {len(hit)} 行 → {out_path}")

    send_notification(
        "EC基因提取通知",
        f"脚本: 6.9_extract_EC_genes.py\n"
        f"服务器: {socket.gethostname()}\n"
        + "\n".join(outputs),
    )


if __name__ == "__main__":
    main()
