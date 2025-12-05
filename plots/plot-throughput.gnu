# plot-throughput.gnu - Throughput vs Thread Count
#
# Usage: gnuplot -e "scenario='read_only'; mapsize=1000000; pinning='compact'" plots/plot-throughput.gnu

# Default values
if (!exists("scenario")) scenario = "read_only"
if (!exists("mapsize")) mapsize = 1000000
if (!exists("pinning")) pinning = "compact"

# Output
set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/throughput_%s_%d_%s.png", scenario, mapsize, pinning)

# Title and labels
set title sprintf("Throughput: %s (mapsize=%d, pinning=%s)", scenario, mapsize, pinning) font ',16'
set xlabel "Thread Count" font ',14'
set ylabel "Throughput (Million ops/sec)" font ',14'

# Grid and styling
set grid
set key top left box
set style data linespoints

# X-axis (thread counts)
set xtics (1, 2, 4, 8, 16, 32)
set logscale x 2

# Line styles
set style line 1 lc rgb '#0072BD' pt 7 ps 1.5 lw 2  # phmap - blue
set style line 2 lc rgb '#D95319' pt 5 ps 1.5 lw 2  # libcuckoo - orange
set style line 3 lc rgb '#77AC30' pt 9 ps 1.5 lw 2  # dashmap - green

# Data file
datafile = "results/aggregated/summary.csv"

# Plot using awk to filter data
# Note: Uses external filtering since gnuplot's built-in filtering is limited

plot \
    sprintf("< awk -F, 'NR>1 && $1==\"parallel-hashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6, $10/1e6, $11/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2:3:4 with yerrorbars ls 1 title "parallel-hashmap", \
    sprintf("< awk -F, 'NR>1 && $1==\"parallel-hashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with lines ls 1 notitle, \
    sprintf("< awk -F, 'NR>1 && $1==\"libcuckoo\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6, $10/1e6, $11/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2:3:4 with yerrorbars ls 2 title "libcuckoo", \
    sprintf("< awk -F, 'NR>1 && $1==\"libcuckoo\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with lines ls 2 notitle, \
    sprintf("< awk -F, 'NR>1 && $1==\"dashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6, $10/1e6, $11/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2:3:4 with yerrorbars ls 3 title "DashMap", \
    sprintf("< awk -F, 'NR>1 && $1==\"dashmap\" && $2==\"%s\" && $4==%d && $5==\"%s\" {print $3, $7/1e6}' %s", scenario, mapsize, pinning, datafile) \
        using 1:2 with lines ls 3 notitle
