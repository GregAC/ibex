from branch_analysis import *
import sys

def process_trace(trace_filename, trace_elf):
    branch_model_instances = {'static' : StaticBranchPredictModel()}

    results = run_branch_models(trace_filename, trace_elf, branch_model_instances)

    for k, v in results['static'].items():
        print(f"{k}: {v}")

    print(f"mispredict rate: {results['static']['mispredict']/results['static']['branches']}")
    print(f"total branches: {results['static']['branches'] + results['static']['num_jrs']}")

process_trace(sys.argv[1], sys.argv[2])

