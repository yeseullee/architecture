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
#include <set>
#include "system.h"
#include "Vtop.h"

#define STACK_PAGES     (100)

using namespace std;

enum {
    READ   = 0b1,
    WRITE  = 0b0,
    INVAL  = 0b1000,
    MEMORY = 0b0001,
    MMIO   = 0b0011,
    PORT   = 0b0100,
    IRQ    = 0b1110
};

System* System::sys;

System::System(Vtop* top, unsigned ramsize, const char* ramelf, const int argc, char* argv[], int ps_per_clock)
    : top(top), ps_per_clock(ps_per_clock), ramsize(ramsize), max_elf_addr(0), show_console(false), interrupts(0), rx_count(0), ticks(0), ecall_brk(0), errno_addr(NULL)
{
    sys = this;

    char* HAVETLB = getenv("HAVETLB");
    use_virtual_memory = HAVETLB && (toupper(*HAVETLB) == 'Y');

    string ram_fn = string("/vtop-system-")+to_string(getpid());
    ram_fd = shm_open(ram_fn.c_str(), O_RDWR|O_CREAT|O_EXCL, 0600);
    assert(ram_fd != -1);
    assert(shm_unlink(ram_fn.c_str()) == 0);
    assert(ftruncate(ram_fd, ramsize) == 0);
    ram = (char*)mmap(NULL, ramsize, PROT_READ|PROT_WRITE, MAP_SHARED, ram_fd, 0);
    assert(ram != MAP_FAILED);
    if (!use_virtual_memory) ram_virt = ram;
    else ram_virt = (char*)mmap(NULL, ramsize, PROT_NONE, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
    assert(ram_virt != MAP_FAILED);
    top->satp = get_phys_page() << 12;
    top->stackptr = ramsize - 4*MEGA;
    for(int n = 1; n < STACK_PAGES; ++n) virt_to_phy(top->stackptr - PAGE_SIZE*n); // allocate stack pages

    uint64_t* argvp = (uint64_t*)(ram+virt_to_phy(top->stackptr));
    argvp[0] = argc;
    uint64_t dst = top->stackptr + 8/*argc*/ + 8*argc + 8/*envp*/ + 8/*env*/;
    argvp[argc+1] = dst-8; // envp
    argvp[argc+2] = 0; // env array
    for(int arg = 0; arg < argc; ++arg) {
        argvp[arg+1] = dst;
        char* src = argv[arg];
        do {
            virt_to_phy(dst); // make sure phys page is allocated
            ram_virt[dst] = *src;
            dst++;
        } while(*(src++));
    }
    virt_to_phy(0); // TODO: must initialize auxv vector with AT_RANDOM value.  until then, _dl_random will be a null pointer, so need to prefault address 0

    // load the program image
    if (ramelf) top->entry = load_elf(ramelf);

    ecall_brk = max_elf_addr;

    // create the dram simulator
    dramsim = DRAMSim::getMemorySystemInstance("DDR2_micron_16M_8b_x8_sg3E.ini", "system.ini", "../dramsim2", "dram_result", ramsize / MEGA);
    DRAMSim::TransactionCompleteCB *read_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_read_complete);
    DRAMSim::TransactionCompleteCB *write_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_write_complete);
    dramsim->RegisterCallbacks(read_cb, NULL, NULL);
    dramsim->setCPUClockSpeed(1000ULL*1000*1000*1000/ps_per_clock);
}

System::~System() {
    assert(munmap(ram, ramsize) == 0);
    assert(close(ram_fd) == 0);

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

    if (ticks % (ps_per_clock * 1000) == 0) {
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
                            int val = (top->bus_req >> (8*shift)) & 0xffff;
                            //cerr << "val=" << std::hex << val << endl;
                            attron(val & ~0xff);
                            mvaddch(screenpos / 160, screenpos % 160 + shift/2, val & 0xff);
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
            xfer_addr = top->bus_req & ~0x3fULL;
            if (xfer_addr > (ramsize - 64)) {
                cerr << "Invalid 64-byte access, address " << std::hex << xfer_addr << " is beyond end of memory at " << ramsize << endl;
                Verilated::gotFinish(true);
            } else if (addr_to_tag.find(xfer_addr)!=addr_to_tag.end()) {
                cerr << "Access for " << std::hex << xfer_addr << " already outstanding. Ignoring..." << endl;
            } else {
                assert(
                        dramsim->addTransaction(isWrite, xfer_addr)
                      );
                //cerr << "add transaction " << std::hex << xfer_addr << " on tag " << top->bus_reqtag << endl;
                if (!isWrite) addr_to_tag[xfer_addr] = make_pair(top->bus_req, top->bus_reqtag);
            }
            break;

        case MMIO:
            xfer_addr = top->bus_req;
            assert(!(xfer_addr & 7));
            if (!isWrite) tx_queue.push_back(make_pair(*((uint64_t*)(&ram[xfer_addr])),top->bus_reqtag)); // hack - real I/O takes time
            break;

        default:
            cerr << "Unknown command" << std::hex << cmd << endl;
            Verilated::gotFinish(true);
        };
    } else {
        top->bus_reqack = 0;
        rx_count = 0;
    }
}

void System::dram_read_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
    map<uint64_t, pair<uint64_t, int> >::iterator tag = addr_to_tag.find(address);
    assert(tag != addr_to_tag.end());
    uint64_t orig_addr = tag->second.first;
    for(int i = 0; i < 64; i += 8)
        tx_queue.push_back(make_pair(*((uint64_t*)(&ram[((orig_addr&(~63))+((orig_addr+i)&63))])),tag->second.second));
    addr_to_tag.erase(tag);
}

void System::dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
    do_finish_write(address, 64);
}

void System::set_errno(const int new_errno) {
    if (errno_addr) {
        *errno_addr = new_errno;
        invalidate((char*)errno_addr - ram);
    }
}

void System::invalidate(const uint64_t phy_addr) {
    tx_queue.push_front(make_pair(phy_addr, INVAL << 8));
}

uint64_t System::get_phys_page() {
    int page_no;
    do {
        page_no = rand()%(ramsize/PAGE_SIZE);
    } while(phys_page_used[page_no]);
    phys_page_used[page_no] = true;
    return page_no;
}

#define VM_DEBUG 0

uint64_t System::get_pte(uint64_t base_addr, int vpn, bool isleaf, bool& allocated) {
    uint64_t addr = base_addr + vpn*8;
    uint64_t pte = *(uint64_t*) & ram[addr];
    uint64_t page_no = pte >> 10;
    if(!(pte & VALID_PAGE)) {
        page_no = get_phys_page();
        if (isleaf)
            (*(uint64_t*)&ram[addr]) = (page_no<<10) | VALID_PAGE;
        else
            (*(uint64_t*)&ram[addr]) = (page_no<<10) | VALID_PAGE_DIR;
        pte = *(uint64_t*) & ram[addr];
        if (VM_DEBUG) {
            cout << "Addr:" << std::dec << addr << endl;
            cout << "Initialized page no " << std::dec << page_no << endl;
        }
        allocated = isleaf;
    } else {
        allocated = false;
    }
    assert(page_no < ramsize/PAGE_SIZE);
    return pte;
}

uint64_t System::virt_to_phy(const uint64_t virt_addr) {

    if (!use_virtual_memory) {
      assert(virt_addr < ramsize);
      return virt_addr;
    }

    bool allocated;
    uint64_t pt_base_addr = top->satp;
    uint64_t phy_offset = virt_addr & (PAGE_SIZE-1);
    uint64_t tmp_virt_addr = virt_addr >> 12;
    for(int i = 0; i < 4; i++) {
        int vpn = (tmp_virt_addr & (0x01ff << 9*(3-i))) >> 9*(3-i);
        uint64_t pte = get_pte(pt_base_addr, vpn, i == 3, allocated);
        pt_base_addr = ((pte&0x0000ffffffffffff)>>10)<<12;
    }
    if (allocated) {
        void* new_virt = ram_virt + (virt_addr & ~(PAGE_SIZE-1));
        assert(mmap(new_virt, PAGE_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_FIXED, ram_fd, pt_base_addr) == new_virt);
    }
    assert((pt_base_addr | phy_offset) < ramsize);
    return (pt_base_addr | phy_offset);
}

void System::load_segment(const int fd, const size_t memsz, const size_t filesz, uint64_t virt_addr) {
    if (VM_DEBUG) cout << "Read " << std::dec << filesz << " bytes at " << std::hex << virt_addr << endl;
    for(size_t i = 0; i < memsz; ++i) virt_to_phy(virt_addr + i); // prefault
    assert(filesz == read(fd, &ram_virt[virt_addr], filesz));
}

uint64_t System::load_elf(const char* filename) {

    // check libelf version
    if (elf_version(EV_CURRENT) == EV_NONE) {
        cerr << "ELF binary out of date" << endl;
        exit(-1);
    }

    // open the elf file
    int fd = open(filename, O_RDONLY);
    assert(fd != -1);

    // start reading the file
    Elf* elf = elf_begin(fd, ELF_C_READ, NULL);
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
        while((scn = elf_nextscn(elf, scn)) != NULL) {
            GElf_Shdr shdr;
            gelf_getshdr(scn, &shdr);
            if (shdr.sh_type != SHT_PROGBITS) continue;
            if (!(shdr.sh_flags & SHF_EXECINSTR)) continue;

            // copy segment content from file to memory
            assert(-1 != lseek(fd, shdr.sh_offset, SEEK_SET));
            load_segment(fd, shdr.sh_size, shdr.sh_size, 0);
            break; // just load the first one
        }
    } else {
        for(unsigned phn = 0; phn < elf_header.e_phnum; phn++) {
            GElf_Phdr phdr;
            gelf_getphdr(elf, phn, &phdr);

            switch(phdr.p_type) {
            case PT_LOAD: {
                if ((phdr.p_vaddr + phdr.p_memsz) > ramsize) {
                    cerr << "Not enough 'physical' ram" << endl;
                    exit(-1);
                }
                cout << "Loading ELF header #" << phn << "."
                    << " offset: "   << phdr.p_offset
                    << " filesize: " << phdr.p_filesz
                    << " memsize: "  << phdr.p_memsz
                    << " vaddr: "    << std::hex << phdr.p_vaddr << std::dec
                    << " paddr: "    << std::hex << phdr.p_paddr << std::dec
                    << " align: "    << phdr.p_align
                    << endl;

                // copy segment content from file to memory
                assert(-1 != lseek(fd, phdr.p_offset, SEEK_SET));
                load_segment(fd, phdr.p_memsz, phdr.p_filesz, phdr.p_vaddr);

                if (max_elf_addr < (phdr.p_vaddr + phdr.p_memsz))
                    max_elf_addr = (phdr.p_vaddr + phdr.p_memsz);
                break;
            }
            case PT_TLS:
                errno_addr = (int*)(ram + phdr.p_vaddr + 0x20 /* errno, grep ".*TLS.* errno$" */);
                cout << "Setting errno_addr to " << std::hex << errno_addr << " (TLS at " << phdr.p_vaddr << "+0x20)" << endl;
                break;
            case PT_DYNAMIC:
            case PT_NOTE:
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
        max_elf_addr = ((max_elf_addr + PAGE_SIZE-1) / PAGE_SIZE) * PAGE_SIZE;
    }
    // finalize
    close(fd);
    return elf_header.e_entry /* entry point */;
}
