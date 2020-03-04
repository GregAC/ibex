from branch_analysis import *

def process_embench(embench_out_path, results_filename):
    embench_results = open(results_filename, 'w')
    embench_results.write('benchmark, branches, jmps, jrs, taken conditional branches')
    model_columns = []

    for bm in branch_models.keys():
        embench_results.write(f',{bm} t_mp')
        embench_results.write(f',{bm} nt_mp')
        embench_results.write(f',{bm} t_p')
        embench_results.write(f',{bm} nt_p')
        model_columns.append(bm)

    embench_results.write('\n')

    embench_out_root = pathlib.Path(embench_out_path)
    embench_out_dirs = [p for p in embench_out_root.iterdir() if p.is_dir()]

    for embench_out_dir in embench_out_dirs:
        trace_filename = embench_out_dir / 'trace_core_00000000.log'
        elf_filename = embench_out_dir / embench_out_dir.name

        branch_model_instances = get_branch_model_instances()

        branch_results = run_branch_models(trace_filename, elf_filename,
                branch_model_instances)


        if not branch_results:
            print(f"Error: failure running branch models for {embench_out_dir.name}")
            continue

        embench_results.write(f"{embench_out_dir.name},")
        embench_results.write(f"{branch_results[model_columns[0]]['branches']},")
        embench_results.write(f"{branch_results[model_columns[0]]['num_jmps']},")
        embench_results.write(f"{branch_results[model_columns[0]]['num_jrs']},")
        embench_results.write(f"{branch_results[model_columns[0]]['num_taken_conditional_branches']}")

        for bm in model_columns:
            embench_results.write(f",{branch_results[bm]['t_mp']}")
            embench_results.write(f",{branch_results[bm]['nt_mp']}")
            embench_results.write(f",{branch_results[bm]['t_p']}")
            embench_results.write(f",{branch_results[bm]['nt_p']}")

        embench_results.write("\n")
        embench_results.flush()

    embench_results.close()

process_embench(sys.argv[1], sys.argv[2])
