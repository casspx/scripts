"""
Portworx journal log parser
- Takes input file from command arg or file named p.log
- Known patterns are stored in procpl_lib module
- Processes the log file by matching known patterns
- Prints patterns found and associated fix or runbook
Written by C2
May 2023
"""

import getopt, sys
from concurrent.futures import ThreadPoolExecutor

class LogParser:
    import procpl_lib as plib

    def __init__(self):
        print(' '.join(sys.argv))
        arg_list = sys.argv[1:]
        options = "f:s:h"
        long_options = ["file=", "stack=", "help"]
        self.component = ""
        self.fname = ""
        self.etcd_found = []
        self.dmthin_found = []
        self.nfs_found = []
        self.lic_found = []
        self.inst_found = []

        try:
            if len(sys.argv) == 1:
                self.fname = "p.log"
                self.component = "all"
            else:
                arguments, values = getopt.getopt(arg_list, options, long_options)
                for current_arg, current_val in arguments:
                    if current_arg in ("-h", "--help"):
                        print("Usage: procpl.py -f,--filename <log filename> -s,--stack <kvdb|dmthin|nfs|lic|install|all>")
                        print("It looks for a file named \"p.log\" in the current dir if no argument is given and runs full scan")
                        sys.exit()
                    if current_arg in ("-f", "--file"):
                        self.fname = current_val
                    if current_arg in ("-s", "--stack"):
                        self.component = current_val
                if self.component not in self.plib.px_component or not self.fname:
                    print(f"Invalid arguments. Usage: {sys.argv[0]} --help")
                    sys.exit()
        except Exception as err:
            print(err)
            print(f"Invalid arguments. Usage: {sys.argv[0]} --help")
            sys.exit()
            
    def parse_log_file(self):
        counter = 0

        try:
            with open(self.fname, 'r') as file:
                if self.component == "all":
                    print("Starting full scan")
                else:
                    print("Starting", self.component + " scan")
                for line in file:
                    if self.component == "kvdb":
                        self.plib.etcd_psearch(self.etcd_found, line)
                    if self.component == "dmthin":
                        self.plib.dmthin_psearch(self.dmthin_found, line)
                    if self.component == "nfs":
                        self.plib.nfs_psearch(self.nfs_found, line)
                    if self.component == "lic":
                        self.plib.lic_psearch(self.lic_found, line)
                    if self.component == "install":
                        self.plib.inst_psearch(self.inst_found, line)
                    if self.component == "all":
                        pool = ThreadPoolExecutor(5)
                        etcd = pool.submit(self.plib.etcd_psearch, self.etcd_found, line)
                        dmthin = pool.submit(self.plib.dmthin_psearch, self.dmthin_found, line)
                        nfs = pool.submit(self.plib.nfs_psearch, self.nfs_found, line)
                        lic = pool.submit(self.plib.lic_psearch, self.lic_found, line)
                        install = pool.submit(self.plib.inst_psearch, self.inst_found, line)
                        #etcd.result()
                    counter += 1
            print("Processed", counter, "lines")
        except Exception as err:
            print(err)
            sys.exit("parse_log_file exited")
            
    def print_found_re(self):
        if self.etcd_found:
            for count, value in enumerate(self.etcd_found):
                print(f"{'kvdb:'}{count}", value)
            print("Please see", self.plib.rb_etcd1)
        if self.dmthin_found:
            for count, value in enumerate(self.dmthin_found):
                print(f"{'dmthin:'}{count}", value)
            print("Please see", self.plib.rb_dmthin1)
        if self.nfs_found:
            for count, value in enumerate(self.nfs_found):
                print(f"{'nfs:'}{count}", value)
            print("Please see", self.plib.rb_nfs1)
        if self.lic_found:
            for count, value in enumerate(self.lic_found):
                print(f"{'lic:'}{count}", value)
            print("Please see", self.plib.rb_lic1)
        if self.inst_found:
            for count, value in enumerate(self.inst_found):
                print(f"{'install:'}{count}", value)
            print("Please see", self.plib.rb_install1)
        if self.plib.pattern_found == 0:
            print("No patterns found")
        else:
            print("Total log pattern/s found :", self.plib.pattern_found)
            

if __name__ == '__main__':
    run = LogParser()
    run.parse_log_file()
    run.print_found_re()
