#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>
#include <gelf.h>
#include <libelf.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <assert.h>
#include <stdlib.h>
#include <iostream>
#include <arpa/inet.h>
#include <ncurses.h>
#include "system.h"
#include "syscall.h"
#include "Vtop.h"

using namespace std;

/**
 * Bus request tag fields
 */
enum {
    READ   = 0b1,
    WRITE  = 0b0,
    MEMORY = 0b0001,
    MMIO   = 0b0011,
    PORT   = 0b0100,
    IRQ    = 0b1110
};

#ifndef be32toh
#define be32toh(x)      ((u_int32_t)ntohl((u_int32_t)(x)))
#endif

static __inline__ u_int64_t cse502_be64toh(u_int64_t __x) { return (((u_int64_t)be32toh(__x & (u_int64_t)0xFFFFFFFFULL)) << 32) | ((u_int64_t)be32toh((__x & (u_int64_t)0xFFFFFFFF00000000ULL) >> 32)); }

/** Current simulation time */
uint64_t main_time = 0;
const int ps_per_clock = 500;
double sc_time_stamp() {
    return main_time;
}

static long ecall_ram = NULL;
static long ecall_brk = NULL;
static unsigned ecall_ramsize = 0;

System::System(Vtop* top, unsigned ramsize, const char* ramelf, const int argc, char* argv[], int ps_per_clock)
    : top(top), ramsize(ramsize), max_elf_addr(0), show_console(false), interrupts(0), rx_count(0)
{
    ram = (char*) malloc(ramsize);
    assert(ram);
    top->stackptr = (uint64_t)ram + ramsize - 4*MEGA;

    // load the program image
    if (ramelf) top->entry = load_elf(ramelf);

    ecall_ram = (long)ram;
    ecall_ramsize = ramsize;
    ecall_brk = (long)ram + max_elf_addr;

    // create the dram simulator
    dramsim = DRAMSim::getMemorySystemInstance("DDR2_micron_16M_8b_x8_sg3E.ini", "system.ini", "../dramsim2", "dram_result", ramsize / MEGA);
    DRAMSim::TransactionCompleteCB *read_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_read_complete);
    DRAMSim::TransactionCompleteCB *write_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_write_complete);
    dramsim->RegisterCallbacks(read_cb, NULL, NULL);
    dramsim->setCPUClockSpeed(1000ULL*1000*1000*1000/ps_per_clock);
}

System::~System() {
    free(ram);
    
    if (show_console) {
        sleep(2);
        endwin();
    }
}

void System::console() {
    show_console = true;
    if (show_console) {
        initscr();
        start_color();
        noecho();
        cbreak();
        timeout(0);
    }
}

void System::tick(int clk) {
    
    if (top->reset && top->bus_reqcyc) {
        cerr << "Sending a request on RESET. Ignoring..." << endl;
        return;
    }
    
    if (!clk) {
        if (top->bus_reqcyc) {
            // hack: blocks ACK if /any/ memory channel can't accept transaction
            top->bus_reqack = dramsim->willAcceptTransaction();            
            // if trnasfer is in progress, can't change mind about willAcceptTransaction()
            assert(!rx_count || top->bus_reqack); 
        }
        return;
    }

    if (main_time % (ps_per_clock * 1000) == 0) {
        int ch = getch();
        if (ch != ERR) {
            if (!(interrupts & (1<<IRQ_KBD))) {
                interrupts |= (1<<IRQ_KBD);
                tx_queue.push_back(make_pair(IRQ_KBD,(int)IRQ));
                keys.push(ch);
            }
        }
    }

    dramsim->update();    
    if (!tx_queue.empty() && top->bus_respack) tx_queue.pop_front();
    if (!tx_queue.empty()) {
        top->bus_respcyc = 1;
        top->bus_resp = tx_queue.begin()->first;
        top->bus_resptag = tx_queue.begin()->second;
        //cerr << "responding data " << top->bus_resp << " on tag " << std::hex << top->bus_resptag << endl;
    } else {
        top->bus_respcyc = 0;
        top->bus_resp = 0xaaaaaaaaaaaaaaaaULL;
        top->bus_resptag = 0xaaaa;
    }

    if (top->bus_reqcyc) {
        cmd = (top->bus_reqtag >> 8) & 0xf;
        if (rx_count) {
            switch(cmd) {
            case MEMORY:
                *((uint64_t*)(&ram[xfer_addr + (8-rx_count)*8])) = top->bus_req;
                break;
            case MMIO:
                assert(xfer_addr < ramsize);
                *((uint64_t*)(&ram[xfer_addr])) = top->bus_req;
                if (show_console)
                    if ((xfer_addr - 0xb8000) < 80*25*2) {
                        int screenpos = xfer_addr - 0xb8000;
                        for(int shift = 0; shift < 8; shift += 2) {
                            int val = (cse502_be64toh(top->bus_req) >> (8*shift)) & 0xffff;
                            //cerr << "val=" << std::hex << val << endl;
                            attron(val & ~0xff);
                            mvaddch(screenpos / 160, screenpos % 160 + shift/2, val & 0xff );
                        }
                        refresh();
                    }
                break;
            }
            --rx_count;
            return;
        }

        bool isWrite = ((top->bus_reqtag >> 12) & 1) == WRITE;
        if (cmd == MEMORY && isWrite)
            rx_count = 8;
        else if (cmd == MMIO && isWrite)
            rx_count = 1;
        else
            rx_count = 0;
            
        switch(cmd) {
        case MEMORY:
            xfer_addr = top->bus_req;
            assert(!(xfer_addr & 7));
            if (addr_to_tag.find(xfer_addr)!=addr_to_tag.end()) {
                cerr << "Access for " << std::hex << xfer_addr << " already outstanding. Ignoring..." << endl;
            } else {
                assert(
                    dramsim->addTransaction(isWrite, xfer_addr)
                );
                //cerr << "add transaction " << std::hex << xfer_addr << " on tag " << top->bus_reqtag << endl;
                if (!isWrite) addr_to_tag[xfer_addr] = top->bus_reqtag;
            }
            break;

        case MMIO:
            xfer_addr = top->bus_req;
            assert(!(xfer_addr & 7));
            if (!isWrite) tx_queue.push_back(make_pair(*((uint64_t*)(&ram[xfer_addr])),top->bus_reqtag)); // hack - real I/O takes time
            break;

        default:
            assert(0);
        };
    }
    else {
        top->bus_reqack = 0;
        rx_count = 0;
    }
}

void System::dram_read_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
    map<uint64_t, int>::iterator tag = addr_to_tag.find(address);
    assert(tag != addr_to_tag.end());
    for(int i = 0; i < 64; i += 8) {
        //cerr << "fill data from " << std::hex << (address+(i&63)) <<  ": " << tx_queue.rbegin()->first << " on tag " << tag->second << endl;
        tx_queue.push_back(make_pair(*((uint64_t*)(&ram[((address&(~63))+((address+i)&63))])),tag->second));
    }
    addr_to_tag.erase(tag);
}

void System::dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
}

uint64_t System::load_elf(const char* filename) {
    
    // check libelf version
    if (elf_version(EV_CURRENT) == EV_NONE) {
        cerr << "ELF binary out of date" << endl;
        exit(-1);
    }

    // open the elf file
    int fileDescriptor = open(filename, O_RDONLY);
    assert(fileDescriptor != -1);
        
    // start reading the file
    Elf* elf = elf_begin(fileDescriptor, ELF_C_READ, NULL);
    if (NULL == elf) {
        cerr << "Could not initialize the ELF data structures" << endl;
        exit(-1);
    }

    if (elf_kind(elf) != ELF_K_ELF) {
        cerr << "Not an ELF object: " << filename << endl;
        exit(-1);
    }

    GElf_Ehdr elf_header;
    gelf_getehdr(elf, &elf_header);

    if (!elf_header.e_phnum) { // loading simple object file
        Elf_Scn* scn = NULL;
        while ((scn = elf_nextscn(elf, scn)) != NULL) {
            GElf_Shdr shdr;
            gelf_getshdr(scn, &shdr);
            if (shdr.sh_type != SHT_PROGBITS) continue;
            if (!(shdr.sh_flags & SHF_EXECINSTR)) continue;

            // copy segment content from file to memory
            assert(-1 != lseek(fileDescriptor, shdr.sh_offset, SEEK_SET));
            assert(shdr.sh_size == read(fileDescriptor, (void*)(ram + 0/* addr */), shdr.sh_size));
            break; // just load the first one
        }
	} else {
		for (unsigned phn = 0; phn < elf_header.e_phnum; phn++) {
			GElf_Phdr phdr;
			gelf_getphdr(elf, phn, &phdr);

			switch(phdr.p_type) {
			case PT_LOAD:
				if ((phdr.p_vaddr + phdr.p_memsz) > ramsize) {
					cerr << "Not enough 'physical' ram" << endl;
					exit(-1);
				}

				// initialize the memory segment to zero
				memset(ram + phdr.p_vaddr, 0, phdr.p_memsz);
				// copy segment content from file to memory
				assert(-1 != lseek(fileDescriptor, phdr.p_offset, SEEK_SET));
				assert(phdr.p_filesz == read(fileDescriptor, (void*)(ram + phdr.p_vaddr), phdr.p_filesz));

				if (max_elf_addr < (phdr.p_vaddr + phdr.p_filesz))
					max_elf_addr = (phdr.p_vaddr + phdr.p_filesz);

				cerr << "Loaded ELF header #" << phn << "."
					<< " offset: "   << phdr.p_offset
					<< " filesize: " << phdr.p_filesz
					<< " memsize: "  << phdr.p_memsz
					<< " vaddr: "    << std::hex << phdr.p_vaddr << std::dec
					<< " paddr: "    << std::hex << phdr.p_paddr << std::dec
					<< " align: "    << phdr.p_align
					<< endl;
			    break;
            case PT_NOTE:
            case PT_TLS:
			case PT_GNU_STACK:
			case PT_GNU_RELRO:
				// do nothing
                break;
			default:
				cerr << "Unexpected ELF header " << phdr.p_type << endl;
				exit(-1);
			}
		}

		// page-align max_elf_addr
		max_elf_addr = ((max_elf_addr + 4095) / 4096) * 4096;
	}

    // finalize
    close(fileDescriptor);
    return elf_header.e_entry /* entry point */;
}

extern "C" {

#define ECALL_DEBUG 0

void do_ecall(long long a7, long long a0, long long a1, long long a2, long long a3, long long a4, long long a5, long long a6, long long* a0ret) {
#define NASTY_HACK(a) do { if ((a) >= ecall_ram && (a) < (ecall_ram+ecall_ramsize)) { (a) += ecall_ram; if (ECALL_DEBUG) cerr << "Shift " #a " into ram" << endl; } } while(0)
    switch(a7) {
    case __NR_munmap:
        *a0ret = 0; // don't bother unmapping
        return;
    case __NR_brk:
        if (ECALL_DEBUG) cerr << "Allocate " << a0 << " bytes at 0x" << std::hex << ecall_brk << std::dec << endl;
        *a0ret = ecall_brk;
        ecall_brk += a0;
        return;

    case __NR_mmap:
        assert(a0 == 0 && (a3 & MAP_ANONYMOUS)); // only support ANONYMOUS mmap with NULL argument
        return do_ecall(__NR_brk,a1,0,0,0,0,0,0,a0ret);

    default:
        NASTY_HACK(a0);
        NASTY_HACK(a1);
        NASTY_HACK(a2);
        NASTY_HACK(a3);
        NASTY_HACK(a4);
        NASTY_HACK(a5);
        NASTY_HACK(a6);
        break;
    }
    if (ECALL_DEBUG) cerr << "Calling syscall " << a7 << endl;
    *a0ret = syscall(a7, a0, a1, a2, a3, a4, a5, a6);
}

}
