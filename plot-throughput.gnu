# plot-throughput.gnu
# Expects aggregated CSV: agg_results.csv with columns:
# map,scenario,thread_count,mean_ops,ci95
set terminal pngcairo size 1400,800 enhanced font 'Helvetica,14'
set output 'throughput-vs-threads.png'
set title 'Throughput vs Threads (mean ± 95% CI)'
set xlabel 'Threads'
set ylabel 'Throughput (ops/sec)'
set key outside
set grid

# We'll plot three maps, assuming map names are 'dashmap','phmap','libcuckoo'
# Replace column parsing if your CSV layout differs.
# Using gnuplot's stats to filter by map/series is possible if you preprocess.
plot 'agg_results.csv' using (column(4)==0 ? 1/0 : $3):($4) index 0:0 with linespoints lw 2 pt 7 title columnheader(1)
# For a real script, pre-generate separate files per map/series or use gnuplot's statistical filtering.

# Example command to generate files per map:
# awk -F, '$1=="dashmap"{print $3","$4","$5}' agg_results.csv > dashmap.csv
# Then in gnuplot:
# plot 'dashmap.csv' using 1:2:3 with yerrorlines title 'DashMap', \
#      'phmap.csv' using 1:2:3 with yerrorlines title 'Parallel Hashmap', \
#      'libcuckoo.csv' using 1:2:3 with yerrorlines title 'Libcuckoo'