import re
import sys
import subprocess
import pathlib

# Group 1 = Time
# Group 2 = Cycle
# Group 3 = PC
# Group 4 = Insn
# Group 5 = mnemonic
# Group 6 = Instr args
instr_line_re = re.compile(r'^\s+(\d+)\s+(\d+)\s+([\da-f]+)\s+([\da-f]+)\s+([.\w]+)\s+([^\s]+)?')
nm_symbol_line_re = re.compile(r'([a-f\d]+)\s+\w+\s+(\w+)')

def is_branch(instr_line_match):
    return (instr_line_match.group(5)[:3] == 'c.b'
        or instr_line_match.group(5)[0] == 'b')

def is_jmp(instr_line_match):
    return (instr_line_match.group(5)[0] == 'j'
        or instr_line_match.group(5)[:3] == 'c.j')

def is_jr(instr_line_match):
    return (instr_line_match.group(5) == 'c.jr' or
        instr_line_match.group(5) == 'c.jalr' or
        instr_line_match.group(5) == 'jalr' or
        instr_line_match.group(5) == 'jr')


def extract_branch_target(instr_line_match):
    try:
        args = instr_line_match.group(6).split(',')

        if len(args) == 1:
            return int(args[0], 16)
        elif len(args) == 2:
            return int(args[1], 16)
        else:
            return int(args[2], 16)
    except ValueError:
        return None
    except IndexError:
        return None

def extract_pc(instr_line_match):
    return int(instr_line_match.group(3), 16)

def calc_branch_info(trace_lines, start_pc, stop_pc):
    branches = []
    num_jrs = 0
    num_taken_conditional_branches = 0
    last_instr_branch_info = None
    in_region_of_interest = False

    for line in trace_lines:
        instr_line_match = instr_line_re.match(line)

        if instr_line_match:
            cur_instr_pc = extract_pc(instr_line_match)

            if cur_instr_pc == start_pc:
                in_region_of_interest = True
            elif cur_instr_pc == stop_pc:
                print('Left the region')
                in_region_of_interest = False

            if not in_region_of_interest:
                continue

            if last_instr_branch_info:
                taken = False
                if last_instr_branch_info[1] == cur_instr_pc:
                    taken = True

                branches.append((last_instr_branch_info[0],
                    last_instr_branch_info[1], taken))

                if last_instr_branch_info[2] and taken:
                    num_taken_conditional_branches += 1

                last_instr_branch_info = None

            if is_jr(instr_line_match):
                num_jrs += 1
            elif is_branch(instr_line_match) or is_jmp(instr_line_match):
                last_instr_branch_info = (cur_instr_pc,
                        extract_branch_target(instr_line_match),
                        is_branch(instr_line_match))
                if last_instr_branch_info[1] is None:
                    print("WARNING: Couldn't find target on branch instr", line)

        else:
            print('WARNING: No match for', line)

    return (branches, num_jrs, num_taken_conditional_branches)

class CounterTableBranchPredictModel:
    def __init__(self, slots, counter_start, counter_max):
        self.num_slots     = slots
        self.branch_table  = {}
        self.counter_start = counter_start
        self.counter_max   = counter_max
        pass

    def inc_counter(self, pc):
        if self.branch_table[pc][0] != self.counter_max:
            self.branch_table[pc] = (self.branch_table[pc][0] + 1,
                self.branch_table[pc][1])

    def dec_counter(self, pc):
        if self.branch_table[pc][0] != 0:
            self.branch_table[pc] = (self.branch_table[pc][0] - 1,
                self.branch_table[pc][1])

        if self.branch_table[pc][0] == 0:
            self.remove_entry(pc)

    def add_entry(self, pc):
        # Increment age of everything in table
        for k, v in self.branch_table.items():
            self.branch_table[k] = (v[0], v[1] + 1)

        self.branch_table[pc] = (self.counter_start, 0)

    def remove_entry(self, pc):
        entry_age = self.branch_table[pc][1]

        for k, v in self.branch_table.items():
            if v[1] > entry_age:
                self.branch_table[k] = (v[0], v[1] - 1)

        del self.branch_table[pc]

    def get_oldest_entry_pc(self):
        oldest_age = len(self.branch_table) - 1
        return next((k for (k, v) in self.branch_table.items() if v[1] == oldest_age))

    def predict_branch(self, pc, target, taken):
        result = False

        if pc in self.branch_table:
            if(self.branch_table[pc][0] == self.counter_max):
                result = True

            if taken:
                self.inc_counter(pc)
            else:
                self.dec_counter(pc)
        elif taken:
            if len(self.branch_table) == self.num_slots:
                self.remove_entry(self.get_oldest_entry_pc())

            self.add_entry(pc)

            result = False

        return result

class TableBranchPredictModel:
    def __init__(self, slots):
        self.num_slots = slots
        self.branch_table = []
        pass

    def predict_branch(self, pc, target, taken):
        result = pc in self.branch_table

        if not result and taken:
            if len(self.branch_table) == self.num_slots:
                self.branch_table = self.branch_table[1:]

            self.branch_table.append(pc)

        if result and not taken:
            self.branch_table.remove(pc)

        return result

class StaticBranchPredictModel:
    def predict_branch(self, pc, target, taken):
        if(target < pc):
            return True
        else:
            return False

def extract_bench_start_stop(trace_elf):
    try:
        start_pc = None
        stop_pc  = None

        nm_results = subprocess.run(["riscv32-unknown-elf-nm", trace_elf],
            stdout=subprocess.PIPE, universal_newlines=True)

        for line in nm_results.stdout.split('\n'):
            nm_symbol_match = nm_symbol_line_re.match(line)
            if nm_symbol_match:
                if nm_symbol_match.group(2) == 'bench_start':
                    start_pc = int(nm_symbol_match.group(1), 16)
                elif nm_symbol_match.group(2) == 'bench_end':
                    stop_pc = int(nm_symbol_match.group(1), 16)

        return (start_pc, stop_pc)
    except CalledProcessError as e:
        raise('Failure calling nm ' + str(e))
    except TimeoutExpired:
        raise('Timeout from nm')



def run_branch_model(trace_filename, start_pc, stop_pc, branch_model):
    trace_file = open(trace_filename, 'r')
    trace_file_lines = trace_file.readlines()
    trace_file_lines = trace_file_lines[1:]
    branch_info, num_jrs, num_taken_conditional_branches = calc_branch_info(trace_file_lines, start_pc, stop_pc)

    branches = len(branch_info)
    mispredict = 0

    for (pc, target, taken) in branch_info:
        prediction = branch_model.predict_branch(pc, target, taken)
        if prediction != taken:
            mispredict += 1

    return {'branches'                       : branches,
            'mispredict'                     : mispredict,
            'num_jrs'                        : num_jrs,
            'num_taken_conditional_branches' : num_taken_conditional_branches}

def run_branch_models(trace_filename, trace_elf, models):
    print(f"Running models for {trace_filename}, {trace_elf}")

    start_pc = None
    stop_pc  = None
    results  = {}

    try:
        start_pc, stop_pc = extract_bench_start_stop(trace_elf)
    except Exception as e:
        print(f"Error: finding start/stop PC for {trace_elf}: {e}")
        return None

    print(f"start/stop pc: {start_pc:x} {stop_pc:x}")

    if start_pc is None or stop_pc is None:
        print(f"Error: could not find start/stop PC in {trace_elf}")
        return None

    for name, m in models.items():
        print(f"model: {name}")
        result = run_branch_model(trace_filename, start_pc, stop_pc, m)
        results[name] = result

    return results

branch_models = {
        'static': (StaticBranchPredictModel, []),
        'table' : (TableBranchPredictModel, [4]),
        'counter_table_4' : (CounterTableBranchPredictModel, [4,2,3]),
        'counter_table_16' : (CounterTableBranchPredictModel, [16,2,3])
        }

def get_branch_model_instances():
    branch_model_instances = {}

    for bm_name, (bm_class, bm_params) in branch_models.items():
        branch_model_instances[bm_name] = bm_class(*bm_params)

    return branch_model_instances
