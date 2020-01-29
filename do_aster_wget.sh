#!/bin/bash
#
# Use WGET to download EarthData order zip files to an ADAPT $NOBACKUP/data/ASTER/L1A_orders dir from a list of Order IDs
#
# do_aster_wget.sh $NOBACKUP/userfs02/data/ASTER_fairbanks_order_list fairbanks
# next: do_aster_unzip.sh
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
# from: <main_dir>/ASTER/L1A_orders/<batch_name>
#

# List name of the list of order IDs
list_name=$1           # full path to a list of Order IDs
batch_name=${2}
# username for earthdata.nasa.gov
username_earthdata=${3}

# Set up appropriate dirs
main_dir=${4:-'${NOBACKUP}/userfs02/data'}

mkdir -p $main_dir/ASTER
mkdir -p $main_dir/ASTER/L1A_orders
mkdir -p $main_dir/ASTER/L1A_orders/$batch_name

echo ; echo "Copy Order ID list to batch_name dir:"
echo $main_dir/L1A_orders/$batch_name
cp $list_name $main_dir/ASTER/L1A_orders/$batch_name

# Rename list
list_name=$main_dir/ASTER/L1A_orders/$batch_name/`basename $list_name`

if [ -z "$username_earthdata" ] ; then
    echo ; echo "Script call needs a user name to login to earthdata.nasa.gov and download the ASTER L1A scenes you have selected. Exiting." ; echo
    exit 1
else
    echo ; echo "Using WGET to dowload ASTER L1A data from https://earthdata.nasa.gov/"
    echo "Earthdata user: $username_earthdata" ; echo
fi

# Get hostname of your VM to run many instances of script on many VMs with VM-specific subsets of the Order IDs list
# You'd probably need to launch the companion script "do_par.sh" to accomplish this
hostN=`/bin/hostname -s`

# If a hostname specific list exists, use that, otherwise use main list
if [ -e ${list_name}_${hostN} ] ; then
    list_name=${list_name}_${hostN}
fi

# Go to order dir where you will put files
cd $main_dir/ASTER/L1A_orders/$batch_name

# The actual wget cmd to download the data
cmd="wget --user=${username_earthdata} --ask-password -l 1 -r -nc -i ${list_name}"
echo $cmd ; eval $cmd

# Make a scenelist in the L1A_order/<batch_name> subdir
find $PWD -name '*.zip' > scenes.zip.list
