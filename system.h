#ifndef __SYSTEM_H
#define __SYSTEM_H

#include <map>
#include <list>
#include <queue>
#include "DRAMSim2/DRAMSim.h"
#include "Vtop.h"

#define KILO (1024UL)
#define MEGA (1024UL*1024)
#define GIGA (1024UL*1024*1024)

typedef unsigned long __uint64_t;
typedef __uint64_t uint64_t;
typedef unsigned int __uint32_t;
typedef __uint32_t uint32_t;
typedef int __int32_t;
typedef __int32_t int32_t;
typedef unsigned short __uint16_t;
typedef __uint16_t uint16_t;

extern uint64_t main_time;
extern const int ps_per_clock;
double sc_time_stamp();

class System {
    Vtop* top;

    char* ram;
    unsigned int ramsize;
    uint64_t max_elf_addr;

    enum { IRQ_TIMER=0, IRQ_KBD=1 };
    int interrupts;
    std::queue<char> keys;

    bool show_console;

    uint64_t load_elf(const char* filename);

    int cmd, rx_count;
    uint64_t xfer_addr;
    std::map<uint64_t, int> addr_to_tag;
    std::list<std::pair<uint64_t, int> > tx_queue;

    void dram_read_complete(unsigned id, uint64_t address, uint64_t clock_cycle);
    void dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle);
    DRAMSim::MultiChannelMemorySystem* dramsim;
    
public:
    System(Vtop* top, unsigned ramsize, const char* ramelf, int ps_per_clock);
    ~System();

    void console();
    void tick(int clk);

    uint64_t get_ram_address()  { return (uint64_t)ram; }    
    uint64_t get_max_elf_addr() { return max_elf_addr;  }
};

#endif
