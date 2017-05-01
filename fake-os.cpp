#include <iostream>
#include <set>
#include <sys/mman.h>
#include <sys/uio.h>
#include <syscall.h>
#include "system.h"

using namespace std;

extern "C" {

#define MAX_PENDING_WRITES 1000000

    map<long long, char> pending_writes;

    void do_finish_write(long long addr, int size) {
        for(int i = 0; i < size; ++i)
            pending_writes.erase(addr+i);
    }

    void do_pending_write(long long addr, long long val, int size) {
        if (pending_writes.size() > MAX_PENDING_WRITES) {
            for(int i = 0; i < MAX_PENDING_WRITES/10; ++i) {
                auto pw = pending_writes.begin();
                System::sys->ram[pw->first] = pw->second;
                pending_writes.erase(pw);
            }
        }
        for(int ofs = 0; ofs < size; ++ofs) {
            pending_writes[addr+ofs] = (char)val;
            val >>= 8;
        }
    }

#define ECALL_DEBUG 0
#define ECALL_MEMGUARD (10*1024)

    void do_ecall(long long a7, long long a0, long long a1, long long a2, long long a3, long long a4, long long a5, long long a6, long long* a0ret) {
        vector<pair<long long, char[ECALL_MEMGUARD]> > memargs;

        switch(a7) {

        case __NR_brk:
            if (ECALL_DEBUG) cerr << "Allocate " << std::dec << a0 << " bytes at 0x" << std::hex << System::sys->ecall_brk << std::dec << endl;
            *a0ret = System::sys->ecall_brk;
            System::sys->ecall_brk += a0;
            return;

        case __NR_mmap:
            assert(a0 == 0 && (a3 & MAP_ANONYMOUS)); // only support ANONYMOUS mmap with NULL argument
            System::sys->ecall_brk += System::sys->ecall_brk & ~4095; // align to 4K boundary
            return do_ecall(__NR_brk,a1,0,0,0,0,0,0,a0ret);

        case __NR_munmap:
            *a0ret = 0; // don't bother unmapping
            return;

        case __NR_exit_group:
        case __NR_exit:
        case __NR_tgkill:
            Verilated::gotFinish(true);
            return;

        case 1244/*__NR_arch_specific_syscall*/:
            switch(a0) {
                case 1/*RISCV_ATOMIC_CMPXCHG*/:
                    if (*(uint32_t*)&System::sys->ram[a1] == a2) *(uint32_t*)&System::sys->ram[a1] = a3;
                    *a0ret = a2;
                    return;
                case 2/*RISCV_ATOMIC_CMPXCHG64*/:
                    if (*(uint64_t*)&System::sys->ram[a1] == a2) *(uint64_t*)&System::sys->ram[a1] = a3;
                    *a0ret = a2;
                    return;
                default:
                    cerr << "Unsupported arch-specific syscall " << a0 << endl;
                    Verilated::gotFinish(true);
                    return;
            }

        case __NR_rt_sigpending: // a0
        case __NR_rt_sigsuspend: // a0
        case __NR_signalfd: // a1
        case __NR_signalfd4: // a1
        case __NR_sigaltstack: // a0,a1
        case __NR_rt_sigaction: // a1,a2
        case __NR_rt_sigprocmask: // a1,a2
        case __NR_rt_sigtimedwait: // a0,a1,a2
        case __NR_rt_sigqueueinfo:
        case __NR_rt_tgsigqueueinfo:
            if (ECALL_DEBUG) cerr << "NO-OP syscall " << std::dec << a7 << endl;
            *a0ret = 0;
            return;

#define ECALL_OFFSET(v)                                                 \
    do {                                                                \
        memargs.resize(memargs.size()+1);                               \
        memargs.back().first = v;                                       \
        for(int i = 0; i < ECALL_MEMGUARD; ++i) {                       \
            long long srcptr = System::sys->virt_to_phy((v & ~63) + i); \
            memargs.back().second[i] = System::sys->ram[srcptr];        \
        }                                                               \
        v += (long long)System::sys->ram_virt;                          \
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
        case __NR_timerfd_gettime:
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
        case __NR_prlimit64:
        case __NR_name_to_handle_at:
        case __NR_open_by_handle_at:
        case __NR_process_vm_readv:
        case __NR_process_vm_writev:
        case __NR_renameat2:
        case __NR_seccomp:
        case __NR_kexec_file_load:
        case __NR_readv:
        case __NR_preadv:
        case __NR_pwritev:
            cerr << "Unsupported syscall " << std::dec << a7 << endl;
            Verilated::gotFinish(true);
            return;

        default:
            if (ECALL_DEBUG) cerr << "Default syscall " << std::dec << a7 << endl;
            break;
        }
        for(auto& m : memargs)
            for(int i = 0; i < ECALL_MEMGUARD; ++i) {
                auto pw = pending_writes.find((m.first & ~63)+i);
                if (pw == pending_writes.end()) continue;
                System::sys->ram[pw->first] = pw->second;
                pending_writes.erase(pw);
            }
        if (ECALL_DEBUG) cerr << "Calling syscall " << std::dec << a7;

        iovec* iov = (iovec*)a1;
        if (a7 == __NR_writev)
            for(int i = 0; i < a2; ++i)
                iov[i].iov_base = (char*)iov[i].iov_base + (long long)System::sys->ram_virt;

        int old_errno = errno;
        *a0ret = syscall(a7, a0, a1, a2, a3, a4, a5, a6);
        if (old_errno != errno) {
            if (ECALL_DEBUG) cerr << "Changing errno to " << std::dec << errno << endl;
            System::sys->set_errno(errno);
        }

        if (a7 == __NR_writev)
            for(int i = 0; i < a2; ++i)
                iov[i].iov_base = (char*)iov[i].iov_base - (long long)System::sys->ram_virt;

        if (ECALL_DEBUG) cerr << " => " << std::dec << *a0ret << endl;
        set<long long> invalidations;
        for(auto& m : memargs)
            for(int i = 0; i < ECALL_MEMGUARD; ++i) {
                long long srcptr = System::sys->virt_to_phy((m.first & ~63) + i);
                if (m.second[i] != System::sys->ram[srcptr]) {
                    if (ECALL_DEBUG) cerr << "Invalidating " << std::dec << i << " on argument " << std::hex << m.first << "/" << System::sys->ram[srcptr] << endl;
                    invalidations.insert(m.first & ~63);
                }
            }
        for(auto& i : invalidations)
            System::sys->invalidate(i);
    }

}
