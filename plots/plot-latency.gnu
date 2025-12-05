# plot-latency.gnu - Latency Percentiles Comparison
#
# Usage: gnuplot -e "scenario='read_only'; threads=8; mapsize=1000000; pinning='compact'" plots/plot-latency.gnu

if (!exists("scenario")) scenario = "read_only"
if (!exists("threads")) threads = 8
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/latency_%s_%dt_%d_%s.png", scenario, threads, mapsize, pinning)

set title sprintf("Latency Percentiles: %s (%d threads, mapsize=%d)", scenario, threads, mapsize) font ',16'
set xlabel "Implementation" font ',14'
set ylabel "Latency (nanoseconds)" font ',14'

set grid ytics
set key top right box
set style data histogram
set style histogram cluster gap 1
set style fill solid 0.8 border -1

set boxwidth 0.2

# Colors for percentiles
set style line 1 lc rgb '#0072BD'  # p50 - blue
set style line 2 lc rgb '#EDB120'  # p90 - yellow
set style line 3 lc rgb '#D95319'  # p95 - orange
set style line 4 lc rgb '#A2142F'  # p99 - red

datafile = "results/aggregated/summary.csv"

# Extract data for each implementation
# Columns: p50=16, p90=17, p95=18, p99=19

set xtics ("parallel-hashmap" 0, "libcuckoo" 1, "dashmap" 2)

plot \
    sprintf("< awk -F, 'NR>1 && $2==\"%s\" && $3==%d && $4==%d && $5==\"%s\" {print NR-2, $16}' %s", scenario, threads, mapsize, pinning, datafile) \
        using ($1*1-0.3):2:(0.2) with boxes ls 1 title "p50", \
    sprintf("< awk -F, 'NR>1 && $2==\"%s\" && $3==%d && $4==%d && $5==\"%s\" {print NR-2, $17}' %s", scenario, threads, mapsize, pinning, datafile) \
        using ($1*1-0.1):2:(0.2) with boxes ls 2 title "p90", \
    sprintf("< awk -F, 'NR>1 && $2==\"%s\" && $3==%d && $4==%d && $5==\"%s\" {print NR-2, $18}' %s", scenario, threads, mapsize, pinning, datafile) \
        using ($1*1+0.1):2:(0.2) with boxes ls 3 title "p95", \
    sprintf("< awk -F, 'NR>1 && $2==\"%s\" && $3==%d && $4==%d && $5==\"%s\" {print NR-2, $19}' %s", scenario, threads, mapsize, pinning, datafile) \
        using ($1*1+0.3):2:(0.2) with boxes ls 4 title "p99"
