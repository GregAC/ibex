#!/usr/bin/python3

import argparse

mif_header = """WIDTH={0};
DEPTH={1};

ADDRESS_RADIX=DEC;
DATA_RADIX=HEX;

CONTENT BEGIN
"""

def output_mif(mif_file, data):
    mif_file.write(mif_header.format(32, len(data)))

    for a, d in enumerate(data):
        mif_file.write(f'{a} : {d:x};\n')

    mif_file.write('END;\n')

def bin_to_data(bin_file):
    data_bytes = bin_file.read()
    data_words = len(data_bytes) // 4

    if len(data_bytes) % 4:
        data_words += 1

    data = []

    for word in range(data_words):
        data.append(int.from_bytes(data_bytes[word * 4: word * 4 + 4], 'little'))

    return data

def main():
    arg_parser = argparse.ArgumentParser(description='Converts a .bin to a .mif')
    arg_parser.add_argument('bin_file_in')
    arg_parser.add_argument('mif_file_out')

    args = arg_parser.parse_args()

    bin_file = open(args.bin_file_in, 'rb')
    mif_file = open(args.mif_file_out, 'w')

    data = bin_to_data(bin_file)
    output_mif(mif_file, data)

    bin_file.close()
    mif_file.close()

if __name__ == "__main__":
    main()
