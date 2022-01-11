#include <stdio.h>


#define read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })

#define rdtime() read_csr(time)
#define rdcycle() read_csr(cycle)
#define rdinstret() read_csr(instret)


int main(){
    printf("Starting code\n");
    int a[5] = {1,2,3,4,5}; 
    int b[5] = {6,7,8,9,10};
    int size = sizeof(a)/sizeof(*a);
    int r[5];
    for(int i=0; i < size; i++){
        r[i] = a[i]*b[i];
    }
    int inst_count, cycle_count, time_count;
    inst_count = rdinstret();
    cycle_count = rdcycle();
    time_count = rdtime();
    
    printf("Time: %d\nInstruction count: %d\nCycle Count: %d\nIPC: %f\n", time_count, inst_count, cycle_count, ((float)inst_count)/cycle_count);
    printf("Done\n\n");
    return 0;
}
