#!/bin/bash
#
# Use WGET to download EarthData order zip files from a list of order IDs
#
# Example of list of order IDs that is stored is an file:
# https://e4ftl01.cr.usgs.gov/PullDir/030442546866118
# https://e4ftl01.cr.usgs.gov/PullDir/030442547218189
# https://e4ftl01.cr.usgs.gov/PullDir/030442546918811
#
# This script:
#	Makes a mirrored copy of the remote dir grabbing indiv scene zips
#
# do this:
#	find . -name *.zip | wc -l
# to see if count of scene zips matches what you expected
#
# from: /att/gpfsfs/atrepo01/data/hma_data/ASTER/L1A_orders/winter
#

# List name of the list of order IDs
list_name=$1
usr_name=$2

if [ -z "$usr_name" ] ; then
    echo ; echo "Script call needs a user name. Exiting." ; echo
    exit 1
fi

# Get the hostname of your VM in the event that you want to run many instances of this script across VM-specific subsets of the Order IDs list on different VMs
# You'd probably need to launch the companion script "do_par.sh" to accomplish this
hostN=`/bin/hostname -s`
list_name=${list_name}_${hostN}

# The actual wget cmd to download the data
wget --user=$usr_name --ask-password -l 1 -r -nc -i $list_name

# Make a scenelist
#find $PWD -name '*.zip' > scenes.zip.list
