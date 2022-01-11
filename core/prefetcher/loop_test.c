#include <stdio.h>

inline int read_csr(int csr_num) __attribute__((always_inline)) {
    int result;
    asm("csrr %0, %1" : "=r"(result) : "I"(csr_num));
    return result; 
}

int main(){
    printf("Starting code\n");
    int a[5] = {1,2,3,4,5}; 
    int b[5] = {6,7,8,9,10};
    int size = sizeof(a)/sizeof(*a);
    int r[5];
    for(int i=0; i < size; i++){
        r[i] = a[i]*b[i];
    }
    int inst_count = read_csr(2818);
    int cycle_count = read_csr(2816);
    printf("Instruction count: %d\nCycle Count: %d\nIPC: %f", inst_count, cycle_count, ((float)inst_count)/cycle_count);
    printf("Done");
    return 0;
}