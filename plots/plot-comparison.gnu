# plot-comparison.gnu - Multi-scenario Comparison
#
# Usage: gnuplot -e "threads=8; mapsize=1000000; pinning='compact'" plots/plot-comparison.gnu

if (!exists("threads")) threads = 8
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1400,800 enhanced font 'Arial,14'
set output sprintf("results/plots/comparison_%dt_%d_%s.png", threads, mapsize, pinning)

set title sprintf("Performance Comparison: %d threads, %d entries, %s pinning", threads, mapsize, pinning) font ',16'
set xlabel "Scenario" font ',14'
set ylabel "Throughput (Million ops/sec)" font ',14'

set grid ytics
set key top right box
set style data histogram
set style histogram cluster gap 1
set style fill solid 0.8 border -1

set boxwidth 0.25

set style line 1 lc rgb '#0072BD'  # phmap - blue
set style line 2 lc rgb '#D95319'  # libcuckoo - orange
set style line 3 lc rgb '#77AC30'  # dashmap - green

datafile = "results/aggregated/summary.csv"

# Rotate x-axis labels for readability
set xtics rotate by -45

# Scenario order
set xtics ("insert" 0, "read" 1, "read99" 2, "read95" 3, "balanced" 4, "zipfian" 5)

plot \
    sprintf("< awk -F, 'NR>1 && $1==\"parallel-hashmap\" && $3==%d && $4==%d && $5==\"%s\" {if($2==\"insert_only\") x=0; else if($2==\"read_only\") x=1; else if($2==\"read_majority_99\") x=2; else if($2==\"read_majority_95\") x=3; else if($2==\"balanced\") x=4; else if($2==\"zipfian\") x=5; else next; print x, $7/1e6}' %s", threads, mapsize, pinning, datafile) \
        using ($1-0.25):2:(0.25) with boxes ls 1 title "parallel-hashmap", \
    sprintf("< awk -F, 'NR>1 && $1==\"libcuckoo\" && $3==%d && $4==%d && $5==\"%s\" {if($2==\"insert_only\") x=0; else if($2==\"read_only\") x=1; else if($2==\"read_majority_99\") x=2; else if($2==\"read_majority_95\") x=3; else if($2==\"balanced\") x=4; else if($2==\"zipfian\") x=5; else next; print x, $7/1e6}' %s", threads, mapsize, pinning, datafile) \
        using 1:2:(0.25) with boxes ls 2 title "libcuckoo", \
    sprintf("< awk -F, 'NR>1 && $1==\"dashmap\" && $3==%d && $4==%d && $5==\"%s\" {if($2==\"insert_only\") x=0; else if($2==\"read_only\") x=1; else if($2==\"read_majority_99\") x=2; else if($2==\"read_majority_95\") x=3; else if($2==\"balanced\") x=4; else if($2==\"zipfian\") x=5; else next; print x, $7/1e6}' %s", threads, mapsize, pinning, datafile) \
        using ($1+0.25):2:(0.25) with boxes ls 3 title "DashMap"
