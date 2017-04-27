#include <iostream>
#include <string.h>
#include "Vtop.h"
#include "verilated.h"
#include "system.h"
#if VM_TRACE
# include <verilated_vcd_c.h>	// Trace file format header
#endif

#define RAM_SIZE                  (1*GIGA)
#define INIT_STACK_OFFSET         (4*MEGA)
#define INIT_STACK_POINTER        (RAM_SIZE - INIT_STACK_OFFSET)

/** Current simulation time */
double sc_time_stamp() {
    return System::sys->ticks;
}

int main(int argc, char* argv[]) {
	Verilated::commandArgs(argc, argv);

	const char* ramelf = NULL;
	if (argc > 0) ramelf = argv[1];

	Vtop top;
	System sys(&top, RAM_SIZE, ramelf, argc-1, argv+1, 500);

	// (argc, argv) sanity check
	cerr << "===== Printing arguments of the program..." << endl;
	for (int j = 0; j <= argc-1; j++) {
		unsigned long guest_addr = top.stackptr + j * sizeof(uint64_t);
		uint64_t val = *(uint64_t *)(sys.ram_virt + guest_addr);

		if (0 == j) {
			cerr << dec << "== argc: " << val << endl;
		} else {
			char *arg_ptr = sys.ram_virt + val;
			char *arg_ptr1 = arg_ptr;
			while (*arg_ptr++);
			unsigned len = arg_ptr - arg_ptr1;
			cerr << dec << "== argv[" << j-1 << "]: ";
			do_ecall(1/*__NR_write*/, 2, val, len-1, 0, 0, 0, 0, (long long*)&arg_ptr/*dummy*/);
			cerr << endl;
		}
	}
	cerr << "==========================================" << endl;

#if VM_TRACE
	// If verilator was invoked with --trace
	VerilatedVcdC* tfp = NULL;
	Verilated::traceEverOn(true);
	VL_PRINTF("Enabling waves...\n");
	tfp = new VerilatedVcdC;
	assert(tfp);
	// Trace 99 levels of hierarchy
	top.trace (tfp, 99);
	tfp->spTrace()->set_time_resolution("1 ps");
	// Open the dump file
	tfp->open ("../trace.vcd");
#define TFP_DUMP if (tfp) tfp->dump(sys.ticks);
#else
#define TFP_DUMP
#endif

#define TICK() do {                    \
		top.clk = !top.clk;                \
		top.eval();                        \
		TFP_DUMP                           \
		sys.ticks += sys.ps_per_clock/4;   \
		sys.tick(top.clk);                 \
		top.eval();                        \
		TFP_DUMP                           \
		sys.ticks += sys.ps_per_clock/4;   \
	} while(0)

	top.reset = 1;
	top.clk = 0;
	TICK(); // 1
	TICK(); // 0
	TICK(); // 1
	top.reset = 0;

	const char* SHOWCONSOLE = getenv("SHOWCONSOLE");
	if (SHOWCONSOLE?(atoi(SHOWCONSOLE)!=0):0) sys.console();

	while (sys.ticks/sys.ps_per_clock < 2000*GIGA && !Verilated::gotFinish()) {
		TICK();
	}

	top.final();

#if VM_TRACE
	if (tfp) tfp->close();
	delete tfp;
#endif

	return 0;
}
