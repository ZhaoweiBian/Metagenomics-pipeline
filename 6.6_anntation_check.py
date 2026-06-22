#!/usr/bin/env python3
"""eggNOG 注释质量检查：KO 统计与异常检测。"""
import argparse
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


def main():
    project_root = os.environ.get("PROJECT_ROOT", "/data1/bianzw/hlbw")
    default_annot = os.path.join(
        project_root,
        "contig_function/gene_quant/protein_function/eggNOG/eggnog.emapper.annotations",
    )

    parser = argparse.ArgumentParser(description="eggNOG annotation QC check")
    parser.add_argument("-i", "--input", default=default_annot, help="eggNOG annotations file")
    args = parser.parse_args()

    annot = load_annotations(args.input)
    print("列名:", annot.columns.tolist())

    if "KEGG_ko" not in annot.columns:
        raise ValueError("未找到 KEGG_ko 列")

    ko_col = annot["KEGG_ko"].dropna().astype(str).str.strip()
    ko_col = ko_col[ko_col != "-"]
    ko_counts = ko_col.apply(lambda x: len(x.split(",")))

    print(f"\n有效注释: {len(ko_col)}")
    print(f"单一KO: {(ko_counts == 1).sum()}")
    print(f"多KO: {(ko_counts > 1).sum()} ({(ko_counts > 1).mean():.4f})")
    print("\nKO数量分布:")
    print(ko_counts.value_counts().sort_index())

    all_kos = ko_col.str.split(",").explode().str.strip()
    abnormal = all_kos[~all_kos.str.match(r"ko:K\d+", na=False)]
    print(f"\n异常KO种类: {abnormal.nunique()}")
    if abnormal.nunique() > 0:
        print("示例:", abnormal.unique()[:10])

    send_notification(
        "eggNOG注释质量检查通知",
        f"脚本: 6.6_anntation_check.py\n"
        f"服务器: {socket.gethostname()}\n"
        f"有效注释: {len(ko_col)}\n"
        f"异常KO种类: {abnormal.nunique()}\n"
        f"输入: {args.input}",
    )


if __name__ == "__main__":
    main()
