/* Host-only real CPU x86-64 MOV witness. NOT native HolyC AOT. */
#include <windows.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern uint64_t dbopt_stock_loop(uint64_t);
extern uint64_t dbopt_candidate_loop(uint64_t);
extern char dbopt_stock_inner_begin, dbopt_stock_inner_end;
extern char dbopt_candidate_inner_begin, dbopt_candidate_inner_end;

static int cmp_doubles(const void *left, const void *right) {
    double a = *(const double *)left;
    double b = *(const double *)right;
    return (a > b) - (a < b);
}

static double sample(uint64_t (*f)(uint64_t), uint64_t seed,
                     LARGE_INTEGER frequency, volatile uint64_t *sink) {
    LARGE_INTEGER t0, t1;
    QueryPerformanceCounter(&t0);
    *sink ^= f(seed);
    QueryPerformanceCounter(&t1);
    return (double)(t1.QuadPart - t0.QuadPart) * 1000.0 /
           (double)frequency.QuadPart;
}

int main(void) {
    const int rounds = 15;
    double stock[15], candidate[15];
    LARGE_INTEGER frequency;
    volatile uint64_t sink = 0;
    size_t original = (uintptr_t)&dbopt_stock_inner_end -
                      (uintptr_t)&dbopt_stock_inner_begin;
    size_t improved = (uintptr_t)&dbopt_candidate_inner_end -
                      (uintptr_t)&dbopt_candidate_inner_begin;
    if (original != 9 || improved != 6 ||
        dbopt_stock_loop(0x123456789abcdef0ULL) != 0x2468acf13579bde0ULL ||
        dbopt_candidate_loop(0x123456789abcdef0ULL) != 0x2468acf13579bde0ULL ||
        !QueryPerformanceFrequency(&frequency)) {
        fprintf(stderr, "host x64 assembly semantic/size proof failed\n");
        return 2;
    }
    for (int i = 0; i < 3; i++) {
        sink ^= dbopt_stock_loop(0x1234);
        sink ^= dbopt_candidate_loop(0x1234);
    }
    for (int i = 0; i < rounds; i++) {
        if (i & 1) {
            candidate[i] = sample(dbopt_candidate_loop, 0x1234, frequency, &sink);
            stock[i] = sample(dbopt_stock_loop, 0x1234, frequency, &sink);
        } else {
            stock[i] = sample(dbopt_stock_loop, 0x1234, frequency, &sink);
            candidate[i] = sample(dbopt_candidate_loop, 0x1234, frequency, &sink);
        }
    }
    qsort(stock, rounds, sizeof(double), cmp_doubles);
    qsort(candidate, rounds, sizeof(double), cmp_doubles);
    printf("{\"host\":\"win64-x86-64\",\"iterations_per_sample\":10000000,"
           "\"samples_per_variant\":15,\"baseline_move_bytes\":%zu,"
           "\"candidate_move_bytes\":%zu,\"bytes_removed_per_iteration\":%zu,"
           "\"baseline_median_ms\":%.6f,\"candidate_median_ms\":%.6f,"
           "\"speed_ratio_baseline_over_candidate\":%.6f,\"sink\":%" PRIu64 ","
           "\"native_holyc_compilation_observed\":false}\n",
           original, improved, original - improved,
           stock[rounds/2], candidate[rounds/2],
           stock[rounds/2] / candidate[rounds/2], sink);
    return 0;
}
