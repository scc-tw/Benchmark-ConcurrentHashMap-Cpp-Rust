# plot-scalability.gnu - Scalability (Normalized Speedup)
#
# Usage: gnuplot -e "scenario='insert_only'; mapsize=1000000; pinning='compact'" plots/plot-scalability.gnu

if (!exists("scenario")) scenario = "insert_only"
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/scalability_%s_%d_%s.png", scenario, mapsize, pinning)

set title sprintf("Scalability: %s (mapsize=%d, pinning=%s)", scenario, mapsize, pinning) font ',16'
set xlabel "Thread Count" font ',14'
set ylabel "Speedup (relative to 1 thread)" font ',14'

set grid
set key top left box
set style data linespoints

set xtics (1, 2, 4, 8, 16, 32)
set logscale x 2
set logscale y 2

set style line 1 lc rgb '#0072BD' pt 7 ps 1.5 lw 2
set style line 2 lc rgb '#D95319' pt 5 ps 1.5 lw 2
set style line 3 lc rgb '#77AC30' pt 9 ps 1.5 lw 2
set style line 4 lc rgb '#999999' dt 2 lw 1.5  # Linear scaling reference

datafile = "results/aggregated/summary.csv"

# Linear scaling reference line
set arrow from 1,1 to 32,32 nohead ls 4
set label "Linear scaling" at 20,25 font ',10' tc rgb '#999999'

# Plot speedup (throughput at N threads / throughput at 1 thread)
# This requires preprocessing to get baseline throughput

plot \
    sprintf("< awk -F, 'NR>1 && $1==\"parallel-hashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {if($3==1) base=$7; print $3, $7/base}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with linespoints ls 1 title "parallel-hashmap", \
    sprintf("< awk -F, 'NR>1 && $1==\"libcuckoo\" && $2==\"%s\" && $4==%d && $5==\"%s\" {if($3==1) base=$7; print $3, $7/base}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with linespoints ls 2 title "libcuckoo", \
    sprintf("< awk -F, 'NR>1 && $1==\"dashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {if($3==1) base=$7; print $3, $7/base}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with linespoints ls 3 title "DashMap"
