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
#include <syscall.h>
#include <set>
#include "system.h"
#include "Vtop.h"

using namespace std;

/**
 * Bus request tag fields
 */
enum {
    INVAL  = 0b100,
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

System* sys;
static long long ecall_brk = NULL;

list<pair<uint64_t, int> > tx_queue;

System::System(Vtop* top, unsigned ramsize, const char* ramelf, const int argc, char* argv[], int ps_per_clock)
    : top(top), ramsize(ramsize), max_elf_addr(0), show_console(false), interrupts(0), rx_count(0)
{
    sys = this;

    char* HAVETLB = getenv("HAVETLB");
    use_virtual_memory = HAVETLB && (toupper(*HAVETLB) == 'Y');

    top->satp = satp = get_phys_page();
    ram = (char*)mmap(NULL, ramsize, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, 0, 0);
    assert(ram);
    top->stackptr = virt_to_phy(ramsize - 4*MEGA)+PAGE_SIZE;

    uint64_t* argvp = (uint64_t*)(ram+virt_to_phy(top->stackptr));
    assert((char*)argvp < ram+ramsize);
    argvp[0] = argc;
    char* argvtgt = (char*)&argvp[argc+1];
    for(int arg = 1; arg <= argc; ++arg) {
        argvp[arg] = argvtgt - ram;
        argvtgt = 1+stpcpy(argvtgt, argv[arg-1]);
    }

    // load the program image
    if (ramelf) top->entry = load_elf(ramelf);

    ecall_brk = (long long)ram + max_elf_addr;

    // create the dram simulator
    dramsim = DRAMSim::getMemorySystemInstance("DDR2_micron_16M_8b_x8_sg3E.ini", "system.ini", "../dramsim2", "dram_result", ramsize / MEGA);
    DRAMSim::TransactionCompleteCB *read_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_read_complete);
    DRAMSim::TransactionCompleteCB *write_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_write_complete);
    dramsim->RegisterCallbacks(read_cb, NULL, NULL);
    dramsim->setCPUClockSpeed(1000ULL*1000*1000*1000/ps_per_clock);
}

System::~System() {
    munmap(ram, ramsize);

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
            xfer_addr = top->bus_req & ~0x3fULL;
            //assert(!(xfer_addr & 7));
            if (addr_to_tag.find(xfer_addr)!=addr_to_tag.end()) {
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
            assert(0);
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
    for(int i = 0; i < 64; i += 8) {
        tx_queue.push_back(make_pair(*((uint64_t*)(&ram[((orig_addr&(~63))+((orig_addr+i)&63))])),tag->second.second));
    }
    addr_to_tag.erase(tag);
}

void System::dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
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

uint64_t System::get_pte(uint64_t base_addr, int vpn, bool isleaf) {
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
    }
    assert(page_no < ramsize/PAGE_SIZE);
    return pte;
}

uint64_t System::virt_to_phy(const uint64_t virt_addr) {

    if (!use_virtual_memory) return virt_addr;

    uint64_t phy_offset, tmp_virt_addr;
    uint64_t pt_base_addr = satp;
    phy_offset = virt_addr & 0x0fff;
    tmp_virt_addr = virt_addr >> 12;
    for(int i = 0; i < 4; i++) {
        int vpn = tmp_virt_addr & (0x01ff << 9*(3-i));
        uint64_t pte = get_pte(pt_base_addr, vpn, i == 3);
        pt_base_addr = ((pte&0x0000ffffffffffff)>>10)<<12;
    }
    return (pt_base_addr | phy_offset);
}

uint64_t System::load_elf_parts(int fd, size_t part_size, const uint64_t virt_addr) {
    uint64_t phy_addr = virt_to_phy(virt_addr);
    if (VM_DEBUG) cout << "Virtual addr: " << std::hex << virt_addr << " Physical addr: " << phy_addr << endl;
    size_t len = read(fd, (void*)(ram + phy_addr/* addr */), part_size);
    assert(len == part_size);
    return (virt_addr + part_size);
}

void System::load_segment(const int fd, const size_t header_size, uint64_t virt_addr) {
    int total_full_pages = header_size/PAGE_SIZE;
    size_t part_size = part_size = (((virt_addr >> 12) + 1) << 12) - virt_addr;
    size_t last_page_len = header_size % PAGE_SIZE;
    if (VM_DEBUG) {
        cout << "Total full pages: " << total_full_pages << endl;
        cout << "Total size: " << header_size << endl;
        cout << "Total last page size: " << last_page_len << endl;
    }
    for(int i = 0; i < total_full_pages; i++) {
      virt_addr = load_elf_parts(fd, part_size, virt_addr);
      part_size = 4096;
      assert(virt_addr%4096 == 0);
    }
    if(last_page_len > 0) {
      virt_addr = load_elf_parts(fd, last_page_len, virt_addr);
    }
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
            load_segment(fd, shdr.sh_size, 0);
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
                load_segment(fd, phdr.p_memsz, phdr.p_vaddr);

                if (max_elf_addr < (phdr.p_vaddr + phdr.p_filesz))
                    max_elf_addr = (phdr.p_vaddr + phdr.p_filesz);
                break;
            }
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
    close(fd);
    return elf_header.e_entry /* entry point */;
}

extern "C" {

#define ECALL_DEBUG 0
#define ECALL_MEMGUARD (10*1024)

    map<long long, char> pending_writes;

    void do_pending_write(long long addr, long long val, int size) {
        for(int ofs = 0; ofs < size; ++ofs) {
            pending_writes[addr+ofs] = (char)val;
            val >>= 8;
        }
    }

    void do_ecall(long long a7, long long a0, long long a1, long long a2, long long a3, long long a4, long long a5, long long a6, long long* a0ret) {
        vector<pair<long long, char[ECALL_MEMGUARD]> > memargs;

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

#define ECALL_OFFSET(v)                                              \
    do {                                                             \
        memargs.resize(memargs.size()+1);                            \
        memargs.back().first = v;                                    \
        for(int i = 0; i < ECALL_MEMGUARD; ++i) {                    \
            long long srcptr = sys->virt_to_phy((v & ~63) + i);      \
            if (srcptr >= sys->ramsize) continue;                    \
            memargs.back().second[i] = sys->ram[srcptr];             \
        }                                                            \
        v += (long long)sys->ram;                                    \
    } while(0)

        case __NR_open:
        case __NR_poll:
        case __NR_access:
        case __NR_pipe:
        case __NR_uname:
        case __NR_shmdt:
        case __NR_truncate:
        case __NR_getcwd:
        case __NR_chdir:
        case __NR_mkdir:
        case __NR_rmdir:
        case __NR_creat:
        case __NR_unlink:
        case __NR_chmod:
        case __NR_chown:
        case __NR_lchown:
        case __NR_sysinfo:
        case __NR_times:
        case __NR_rt_sigpending:
        case __NR_rt_sigsuspend:
        case __NR_mknod:
        case __NR__sysctl:
        case __NR_adjtimex:
        case __NR_chroot:
        case __NR_acct:
        case __NR_umount2:
        case __NR_swapon:
        case __NR_swapoff:
        case __NR_sethostname:
        case __NR_setdomainname:
        case __NR_delete_module:
        case __NR_time:
        case __NR_set_tid_address:
        case __NR_mq_unlink:
        case __NR_set_robust_list:
        case __NR_pipe2:
        case __NR_perf_event_open:
        case __NR_getrandom:
        case __NR_memfd_create:
            ECALL_OFFSET(a0);
            break;

        case __NR_read:
        case __NR_write:
        case __NR_fstat:
        case __NR_pread64:
        case __NR_pwrite64:
        case __NR_readv:
        case __NR_writev:
        case __NR_shmat:
        case __NR_getitimer:
        case __NR_connect:
        case __NR_sendmsg:
        case __NR_recvmsg:
        case __NR_bind:
        case __NR_semop:
        case __NR_msgsnd:
        case __NR_msgrcv:
        case __NR_getdents:
        case __NR_getrlimit:
        case __NR_getrusage:
        case __NR_syslog:
        case __NR_getgroups:
        case __NR_setgroups:
        case __NR_ustat:
        case __NR_fstatfs:
        case __NR_sched_setparam:
        case __NR_sched_getparam:
        case __NR_sched_rr_get_interval:
        case __NR_modify_ldt:
        case __NR_setrlimit:
        case __NR_iopl:
        case __NR_flistxattr:
        case __NR_fremovexattr:
        case __NR_io_setup:
        case __NR_getdents64:
        case __NR_timer_gettime:
        case __NR_clock_settime:
        case __NR_clock_gettime:
        case __NR_clock_getres:
        case __NR_epoll_wait:
        case __NR_set_mempolicy:
        case __NR_mq_notify:
        case __NR_inotify_add_watch:
        case __NR_openat:
        case __NR_mkdirat:
        case __NR_mknodat:
        case __NR_fchownat:
        case __NR_unlinkat:
        case __NR_fchmodat:
        case __NR_faccessat:
        case __NR_vmsplice:
        case __NR_signalfd:
        case __NR_timerfd_gettime:
        case __NR_signalfd4:
        case __NR_preadv:
        case __NR_pwritev:
        case __NR_clock_adjtime:
        case __NR_sendmmsg:
        case __NR_finit_module:
        case __NR_sched_setattr:
        case __NR_sched_getattr:
        case __NR_bpf:
            ECALL_OFFSET(a1);
            break;

        case __NR_stat:
        case __NR_lstat:
        case __NR_nanosleep:
        case __NR_rename:
        case __NR_link:
        case __NR_symlink:
        case __NR_readlink:
        case __NR_gettimeofday:
        case __NR_sigaltstack:
        case __NR_utime:
        case __NR_statfs:
        case __NR_pivot_root:
        case __NR_settimeofday:
        case __NR_listxattr:
        case __NR_llistxattr:
        case __NR_removexattr:
        case __NR_lremovexattr:
        case __NR_utimes:
        case __NR_get_mempolicy:
            ECALL_OFFSET(a0);
            ECALL_OFFSET(a1);
            break;

        case __NR_rt_sigaction:
        case __NR_rt_sigprocmask:
        case __NR_setitimer:
        case __NR_accept:
        case __NR_getsockname:
        case __NR_getpeername:
        case __NR_fsetxattr:
        case __NR_fgetxattr:
        case __NR_io_cancel:
        case __NR_timer_create:
        case __NR_mq_getsetattr:
        case __NR_futimesat:
        case __NR_newfstatat:
        case __NR_readlinkat:
        case __NR_utimensat:
        case __NR_accept4:
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a2);
            break;

        case __NR_setresuid:
        case __NR_getresuid:
        case __NR_getresgid:
        case __NR_rt_sigtimedwait:
        case __NR_setxattr:
        case __NR_lsetxattr:
        case __NR_getxattr:
        case __NR_lgetxattr:
        case __NR_add_key:
        case __NR_request_key:
        case __NR_getcpu:
            ECALL_OFFSET(a0);
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a2);
            break;

        case __NR_symlinkat:
            ECALL_OFFSET(a0);
            ECALL_OFFSET(a2);
            break;

        case __NR_futex:
            ECALL_OFFSET(a0);
            ECALL_OFFSET(a3);
            ECALL_OFFSET(a4);
            break;

        case __NR_select:
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a2);
            ECALL_OFFSET(a3);
            ECALL_OFFSET(a4);
            break;

        case __NR_renameat:
        case __NR_linkat:
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a3);
            break;

        case __NR_recvmmsg:
        case __NR_sendto:
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a4);
            break;

        case __NR_recvfrom:
            ECALL_OFFSET(a1);
            ECALL_OFFSET(a4);
            ECALL_OFFSET(a5);
            break;

        case __NR_sendfile:
            ECALL_OFFSET(a2);
            break;

        case __NR_socketpair:
            ECALL_OFFSET(a3);
            break;

        case __NR_setsockopt:
            ECALL_OFFSET(a3);
            break;

        case __NR_getsockopt:
            ECALL_OFFSET(a3);
            ECALL_OFFSET(a4);
            break;

        case __NR_clone:
        case __NR_get_robust_list:
        case __NR_execve:
        case __NR_mincore:
        case __NR_shmctl:
        case __NR_wait4:
        case __NR_msgctl:
        case __NR_rt_sigqueueinfo:
        case __NR_sched_setscheduler:
        case __NR_arch_prctl:
        case __NR_mount:
        case __NR_reboot:
        case __NR_init_module:
        case __NR_quotactl:
        case __NR_sched_setaffinity:
        case __NR_sched_getaffinity:
        case __NR_io_getevents:
        case __NR_io_submit:
        case __NR_semtimedop:
        case __NR_timer_settime:
        case __NR_clock_nanosleep:
        case __NR_epoll_ctl:
        case __NR_mbind:
        case __NR_mq_open:
        case __NR_mq_timedsend:
        case __NR_mq_timedreceive:
        case __NR_kexec_load:
        case __NR_waitid:
        case __NR_migrate_pages:
        case __NR_pselect6:
        case __NR_ppoll:
        case __NR_splice:
        case __NR_move_pages:
        case __NR_epoll_pwait:
        case __NR_timerfd_settime:
        case __NR_rt_tgsigqueueinfo:
        case __NR_prlimit64:
        case __NR_name_to_handle_at:
        case __NR_open_by_handle_at:
        case __NR_process_vm_readv:
        case __NR_process_vm_writev:
        case __NR_renameat2:
        case __NR_seccomp:
        case __NR_kexec_file_load:
            cerr << "Unsupported syscall " << a7 << endl;
            assert(0);

        default:
            if (ECALL_DEBUG) cerr << "Default syscall " << a7 << endl;
            break;
        }
        if (ECALL_DEBUG) cerr << "Calling syscall " << a7 << endl;
        for(auto& m : memargs)
            for(int ofs = 0; ofs < ECALL_MEMGUARD && (m.first & ~63)+ofs < sys->ramsize; ++ofs) {
                auto pw = pending_writes.find((m.first & ~63)+ofs);
                if (pw == pending_writes.end()) continue;
                sys->ram[m.first] = pw->second;
                pending_writes.erase(pw);
            }
        *a0ret = syscall(a7, a0, a1, a2, a3, a4, a5, a6);
        set<long long> invalidations;
        for(auto& m : memargs)
            for(int ofs = 0; ofs < ECALL_MEMGUARD && (m.first & ~63)+ofs < sys->ramsize; ++ofs)
                if (m.second[ofs] != sys->ram[(m.first & ~63) + ofs]) {
                    if (ECALL_DEBUG) cerr << "Invalidating " << ofs << " on argument " << m.first << endl;
                    invalidations.insert(m.first & ~63);
                }
        for(auto& i : invalidations)
            tx_queue.push_front(make_pair(i, INVAL << 13));
    }

}
