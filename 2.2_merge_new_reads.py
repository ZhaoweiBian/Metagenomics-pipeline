#!/usr/bin/env python3
"""合并 Bracken 输出文件为丰度矩阵。"""
import os
import argparse
import pandas as pd


def read_bracken_output(file_path):
    return pd.read_csv(file_path, sep='\t', usecols=['name', 'new_est_reads'])


def merge_results(input_dir, output_file_path, level_suffix):
    all_data = []

    for file_name in os.listdir(input_dir):
        if file_name.endswith(f'.{level_suffix}.bracken'):
            sample_name = file_name.replace(f'.{level_suffix}.bracken', '')
            file_path = os.path.join(input_dir, file_name)
            print(f"Processing sample: {sample_name}")
            df = read_bracken_output(file_path)
            df.set_index('name', inplace=True)
            df.rename(columns={'new_est_reads': sample_name}, inplace=True)
            all_data.append(df)

    if not all_data:
        raise FileNotFoundError(
            f"No files with suffix '.{level_suffix}.bracken' found in {input_dir}"
        )

    combined_df = pd.concat(all_data, axis=1, join='outer').fillna(0)
    combined_df.index.name = 'taxonomy'
    os.makedirs(os.path.dirname(output_file_path) or '.', exist_ok=True)
    combined_df.to_csv(output_file_path, sep='\t')
    print(f"Abundance table saved to: {output_file_path}")


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Merge Bracken output files into a single abundance table."
    )
    parser.add_argument('-i', '--input_dir', type=str, required=True,
                        help="Directory containing .bracken files")
    parser.add_argument('-o', '--output_file', type=str, required=True,
                        help="Output merged abundance table path")
    parser.add_argument('-l', '--level', type=str, required=True,
                        choices=['P', 'C', 'O', 'F', 'G', 'S'],
                        help="Taxonomy level: P/C/O/F/G/S (Phylum/Class/Order/Family/Genus/Species)")
    return parser.parse_args()


def main():
    args = parse_arguments()
    if not os.path.isdir(args.input_dir):
        raise NotADirectoryError(f"Input directory not found: {args.input_dir}")
    merge_results(args.input_dir, args.output_file, args.level)


if __name__ == "__main__":
    main()
