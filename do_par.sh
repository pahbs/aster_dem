#!/bin/bash
#
#
# This will run ASTER L1A do_* scripts in parallel (eventually...)

njobs=5

topDir=/att/gpfsfs/atrepo01/data/hma_data/ASTER/L1A_orders/winter
hostN=`/bin/hostname -s`

cd $topDir

# The scenes list stem
stem=$1

# The list name for a given VM that will run its list of files in parallel
list_name=${stem}_${hostN}

list=$(cat ${topDir}/${list_name})

# Run do_* script
parallel --progress -j $njobs --delay 3 '/att/gpfsfs/atrepo01/data/hma_data/ASTER/L1A_orders/winter/do_wget_list.sh {}' ::: $list