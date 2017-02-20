.PHONY: all run clean submit

RUNELF=/shared/cse502/tests/wp1/prog1.o

TRACE=--trace

VFILES=$(wildcard *.sv)
CFILES=$(wildcard *.cpp)

all: obj_dir/Vtop

obj_dir/Vtop: obj_dir/Vtop.mk
	$(MAKE) -j2 -C obj_dir/ -f Vtop.mk CXX="ccache g++"

obj_dir/Vtop.mk: $(VFILES) $(CFILES) 
	verilator -Wall -Wno-LITENDIAN -Wno-lint -O3 $(TRACE) --no-skip-identical --cc top.sv \
	--exe $(CFILES) /shared/cse502/DRAMSim2/libdramsim.so \
	-CFLAGS -I/shared/cse502 \
	-LDFLAGS -Wl,-rpath=/shared/cse502/DRAMSim2 \
	-LDFLAGS -lncurses -LDFLAGS -lelf

run: obj_dir/Vtop
	cd obj_dir/ && ./Vtop $(RUNELF)

clean:
	rm -rf obj_dir/ dramsim2/results trace.vcd core 

SUBMITTO=/submit
SUBMIT_SUFFIX=-wp1
submit: clean
	rm -f $(USER).tgz
	tar -czvf $(USER).tgz --exclude=.*.sw? --exclude=$(USER).tgz* --exclude=*~ --exclude=.git *
	mv -v $(USER).tgz $(SUBMITTO)/$(USER)$(SUBMIT_SUFFIX)=`date +%F=%T`.tgz
