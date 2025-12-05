# plot-memory.gnu - Memory Efficiency Comparison
#
# Usage: gnuplot -e "threads=1; pinning='compact'" plots/plot-memory.gnu

if (!exists("threads")) threads = 1
if (!exists("pinning")) pinning = "compact"

set terminal pngcairo size 1200,800 enhanced font 'Arial,14'
set output sprintf("results/plots/memory_efficiency_%dt_%s.png", threads, pinning)

set title sprintf("Memory Efficiency: Bytes per Entry (%d thread, %s pinning)", threads, pinning) font ',16'
set xlabel "Map Size" font ',14'
set ylabel "Bytes per Entry" font ',14'

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

# X-axis labels
set xtics ("100K" 0, "1M" 1, "10M" 2)

# Theoretical minimum reference line (16 bytes = u64 key + u64 value)
set arrow from -0.5,16 to 2.5,16 nohead lc rgb '#FF0000' dt 2 lw 2
set label "Theoretical min (16 bytes)" at 2.6,16 font ',10' tc rgb '#FF0000'

# Filter for insert_only scenario (best for memory comparison)
plot \
    sprintf("< awk -F, 'NR>1 && $1==\"parallel-hashmap\" && $2==\"insert_only\" && $3==%d && $5==\"%s\" {if($4==100000) x=0; else if($4==1000000) x=1; else x=2; print x, $21}' %s", threads, pinning, datafile) \
        using ($1-0.25):2:(0.25) with boxes ls 1 title "parallel-hashmap", \
    sprintf("< awk -F, 'NR>1 && $1==\"libcuckoo\" && $2==\"insert_only\" && $3==%d && $5==\"%s\" {if($4==100000) x=0; else if($4==1000000) x=1; else x=2; print x, $21}' %s", threads, pinning, datafile) \
        using 1:2:(0.25) with boxes ls 2 title "libcuckoo", \
    sprintf("< awk -F, 'NR>1 && $1==\"dashmap\" && $2==\"insert_only\" && $3==%d && $5==\"%s\" {if($4==100000) x=0; else if($4==1000000) x=1; else x=2; print x, $21}' %s", threads, pinning, datafile) \
        using ($1+0.25):2:(0.25) with boxes ls 3 title "DashMap"
