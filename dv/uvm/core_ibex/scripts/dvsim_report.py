from metadata import RegressionMetadata, LockedMetadata
from test_run_result import TestRunResult, Failure_Modes

import sys
import os
import pprint
import re
import argparse
import pathlib
import json

XLM_TABLE_HEADER_RE = re.compile(r'(\w+)\*?\s+((?:average)|(?:covered))')
XLM_TABLE_COVERAGE_RE = re.compile(r'\((\d+)/(\d+).*\)')
XLM_TABLE_AVERAGE_RE = re.compile(r'(\d+(?:.\d+)?)%')

IBEX_COVERAGE_METRICS = ['block', 'branch', 'statement', 'expression', 'toggle',
        'fsm', 'assertion']

def parse_xcelium_cov_report(cov_report):
    cov_report_lines = cov_report.splitlines()
    cov_summary_dict = {}
    metrics_start_line = -1
    metric_info = []

    for line_no, line in enumerate(cov_report_lines):
        if "name" in line:
            line_elements = line.lower().split()[1:]
            reduced_line = ' '.join(line_elements)

            for metric_info_match in XLM_TABLE_HEADER_RE.finditer(reduced_line):
                metric_info.append((metric_info_match.group(1),
                    metric_info_match.group(2)))

            # Skip header seperator line
            metrics_start_line = line_no + 2

    if metrics_start_line == -1:
        raise RuntimeError('Could not read xcelium coverage report')

    for line in cov_report_lines[metrics_start_line:]:
        line = re.sub(r'%\s+\(', '%(', line)
        values = line.strip().split()

        module_name = ''

        for i, value in enumerate(values):
            value = value.strip()

            if i == 0:
                module_name = value
                cov_summary_dict[module_name] = {}
                continue

            metric_type = metric_info[i - 1][1]
            metric_name = metric_info[i - 1][0] + '-' + metric_type

            if metric_type == 'covered':
                m = XLM_TABLE_COVERAGE_RE.search(value)
                if m:
                    cov_summary_dict[module_name][metric_name] = {
                            'covered' : int(m.group(1)),
                            'total' : int(m.group(2))
                    }
            else:
                m = XLM_TABLE_AVERAGE_RE.search(value)
                if m:
                    cov_summary_dict[module_name][metric_name] = {
                            'average' : float(m.group(1))
                    }

    return cov_summary_dict

def create_test_summary_dict(metadata):
    test_summary_dict = {}

    for f in metadata.tests_pickle_files:
        test_name = 'UNKNOWN'
        passed = False

        try:
            trr = TestRunResult.construct_from_pickle(f)
            test_name = trr.testname
            passed = trr.passed
        except RuntimeError as e:
            # Tests we cannot unpickle will get the default behaviour of
            # being recorded as a failed 'UNKNOWN' test so just ignore
            # exceptions.
            pass

        if test_name not in test_summary_dict:
            test_summary_dict[test_name] = {'passing': 0, 'failing': 0}

        if passed:
            test_summary_dict[test_name]['passing'] += 1
        else:
            test_summary_dict[test_name]['failing'] += 1

    return test_summary_dict

def add_cov_to_summary(metric_name, metric_data, cov_summary_dict):
    if (f'{metric_name}-covered' in metric_data):
        cov_pct = (100 * metric_data[f'{metric_name}-covered']['covered'] /
            metric_data[f'{metric_name}-covered']['total'])

        cov_summary_dict[metric_name] = cov_pct

def calc_cg_average(cg_report_dict):
    cg_average_total = 0
    num_modules = 0

    for module, metric_data in cg_report_dict.items():
        if 'covergroup-average' not in metric_data:
            continue

        cg_average_total += metric_data['covergroup-average']['average']
        num_modules += 1

    if num_modules > 0:
        return cg_average_total / num_modules

    return None

def create_cov_summary_dict(metadata):
    cov_report_dir = os.path.join(os.path.dirname(metadata.cov_report_log),
            "report")

    cov_report_filename = os.path.join(cov_report_dir, "cov_report.txt")
    cg_report_filename = os.path.join(cov_report_dir, "cov_report_cg.txt")

    cov_report_dict = {}
    cg_report_dict = {}

    with open(cov_report_filename, 'r') as cov_report_file:
        cov_report_dict = parse_xcelium_cov_report(cov_report_file.read())

    with open(cg_report_filename, 'r') as cg_report_file:
        cg_report_dict = parse_xcelium_cov_report(cg_report_file.read())

    cov_summary_dict = {}

    if 'ibex_top' in cov_report_dict:
        for metric_name in IBEX_COVERAGE_METRICS:
            add_cov_to_summary(metric_name, cov_report_dict['ibex_top'],
                    cov_summary_dict)

    cov_summary_dict['covergroup'] = calc_cg_average(cg_report_dict)

    return cov_summary_dict

def create_dvsim_report_dict(tool, block_name, block_variant, test_summary_dict,
        cov_summary_dict):

    dvsim_test_info = []

    for test_name, test_info in test_summary_dict.items():
        total_runs = test_info['passing'] + test_info['failing']

        dvsim_test_info.append({
            'name': test_name,
            'max_runtime_s': 0,
            'simulated_time_us': 0,
            'passing_runs': test_info['passing'],
            'total_runs': total_runs,
            'pass_rate': round((test_info['passing'] / total_runs) * 100, 2)
        })

    return {
        'tool': 'xcelium' if tool == 'xlm' else tool,
        'block_name': block_name,
        'block_variant': block_variant,
        'results' : {
            'coverage': cov_summary_dict,
            'testpoints' : [],
            'unmapped_tests' : dvsim_test_info
            },
    }

def main() -> int:
    """Outputs test results and coverage summary as dvsim style json"""

    parser = argparse.ArgumentParser()
    parser.add_argument('--dir-metadata',
                        type=pathlib.Path, required=True)

    args = parser.parse_args()

    with LockedMetadata(args.dir_metadata, __file__) as md:
        test_summary_dict = create_test_summary_dict(md)
        cov_summary_dict = {}
        if md.simulator == "xlm":
            cov_summary_dict = create_cov_summary_dict(md)
        else:
            print("Warning: Not generating coverage summary, unsupported " \
                    f"simulator {md.simulator}")

        json_content = json.dumps(create_dvsim_report_dict(md.simulator, 'ibex',
            'opentitan', test_summary_dict, cov_summary_dict))

        json_report_filename = md.dir_run/'report.json'

        with open(json_report_filename, 'w') as json_report_file:
            json_report_file.write(json_content)

    return 0

if __name__ == '__main__':
    sys.exit(main())
