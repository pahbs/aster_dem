#!/bin/bash
#
# Proprocess ASTER L1A scenes (unzip and AMES Stereo Pipeline's 'aster2asp') from a batch of zips 
#
# before this script run do_wget_list.sh to download ASTER L1A scenes from earthdata.nasa.gov polygon searches
# [1] Unzip ASTER L1A scenes from ASTER/L1A_orders/<batch_name> to ASTER/L1A/<scenename>
# [2] Create aster camera model
# after this
# Launch like this example:
# pupsh "hostname ~ 'crane101'" "do_aster_preprocess.sh /att/nobackup/pmontesa/userfs02/data/ASTER/L1A_orders/colima/scenes.zip.list batch_colima /att/nobackup/pmontesa/userfs02/data true"


## Check email for "LPDAAC ECS Order Notification Order ID: *****"
## ENTER THE PullDir NUMBER --> note, this is not the ORDERID or the REQUEST ID from the email

################################
#_____Function Definitions_____
################################

preprocess_aster() {

    scenePath=$1
    dir_L1A=$2
    batch_name=${3}
    RM_DIR=$4

    dir_ASTER=$(dirname ${dir_L1A})
    list_name=$dir_ASTER/list_do_aster_stereo_${batch_name}

    echo ; echo "Do ASTER L1A preprocessing..."
    echo "dir_L1A: $dir_L1A"
    echo "dir ASTER: $dir_ASTER"
    echo "ASTER scene is: ${scenePath}"

    now="$(date +'%Y%m%d')"

    # Get scene name of scene zip
    cd ${dir_L1A}

    scene_zip=$(basename $scenePath)
    zip_dir=$(dirname $scenePath)

	if [[ $scene_zip == *"_L1A_"* ]]; then

	    # Copy the AST_L1A zip to the L1A dir
	    cmd="cp $scenePath ${dir_L1A}"

        # Handle bad copy; write to list of bad zips
        if ! eval $cmd &> /dev/null; then
            echo "Bad zip file. Write to list."
            grep -qF "${scenePath}" "${dir_ASTER}/list_bad_zips" || echo "$scenePath" >> "${dir_ASTER}/list_bad_zips"
        else
            eval $cmd
        fi

		# Remove last two elements of filename, creating filenames like this: 'AST_L1A_00308312000062611'
		# Make array of elements in the filename string; eg 'AST_L1A_00308312000062611_20170202145004_32249' ---> [AST L1A 00308312000062611 20170202145004 32249]
		IFS='_' read -ra scene_zip_arr <<< "$scene_zip"
		sceneName=`join_by _ ${scene_zip_arr[@]:0:3}`

		# Format date like this YYYYmmdd
		scene_date=`echo ${sceneName:11:8} | sed -E 's/(.{2})(.{2})(.{4})/\3\1\2/'`
		# Rename scene to this: AST_20000831_00308312000062611
		sceneName=AST_${scene_date}_`join_by _ ${scene_zip_arr[@]:2:1}`

	else
	    sceneName=`echo $scene`
	fi

    if [ "$RM_DIR" = true ] ; then
        rm -rf ${dir_L1A}/${sceneName}
    fi

    if [ ! -d "${dir_L1A}/${sceneName}" ]; then

        echo "[1] UNZIP SCENE..."
        cmd="unzip -oj -d "${dir_L1A}/${sceneName}" ${dir_L1A}/$scene_zip"
        echo $cmd

        # Handle bad unzip; write to list of bad zips
        if ! eval $cmd &> /dev/null; then
            echo "Bad zip file. Write to list."
            grep -qF "${scenePath}" "${dir_ASTER}/list_bad_zips" || echo "$scenePath" >> "${dir_ASTER}/list_bad_zips"
        else
            eval $cmd
            echo "$scene_zip"$'\r'
            echo "Removing all but Band3 data"
            rm ${dir_L1A}/${sceneName}/*Band[12456789]*
            rm ${dir_L1A}/${sceneName}/*Supplement*
            rm ${dir_L1A}/${sceneName}/*.txt
        fi

        echo "[2] CREATE CAMERA MODEL ..."
        echo "${sceneName}"

        if [ -f "${dir_L1A}/${sceneName}/in-Band3N.tif" ]; then
            echo "ASP input files exists already."
        else
            echo "Running aster2asp on $sceneName ..."$'\r'
            aster2asp --threads=15 ${dir_L1A}/${sceneName} -o ${dir_L1A}/${sceneName}/in

            if [ -f "${dir_L1A}/${sceneName}/in-Band3N.tif" ] && [ -f "${dir_L1A}/${sceneName}/in-Band3B.tif" ] ; then
                # Add sceneName to an order list to feed into do_aster_stere.sh
                echo "Add $sceneName to $list_name .."
                grep -qF "${sceneName}" "$list_name" || echo "$sceneName" >> "$list_name"
            fi
        fi

    else
        echo "Dir exists:"
        echo "${sceneName}"
    fi
   
    rm -f ${dir_L1A}/$scene_zip
    rm -f ${dir_L1A}/${sceneName}/*.met
    rm -f ${dir_L1A}/${sceneName}/checksum_report 

}


join_by() { local IFS="$1"; shift; echo "$*"; }

##############################################
#
# Main portion of script
#

# required args
sceneList=$1                            # /path/to/main/zip_list
batch_name=$2                           # Creates a list 4 stereo (a main batch list of scenenames); can be subdivided and processed on VMs with do_aster_stereo.sh

main_dir=${3:-'/att/nobackup/pmontesa/userfs02/data'}           # main dir uder which 'ASTER' subdir will be placed
RM_DIR=${4:-'false'}                    # Remove existing scene dirs and unzip, re-doing all processing for this list of zips? 

mkdir -p $main_dir/ASTER
mkdir -p $main_dir/ASTER/logs
mkdir -p $main_dir/ASTER/L1A

# Get hostname
hostN=`/bin/hostname -s`

if [ -e ${sceneList}_${hostN} ] ; then
    sceneList=${sceneList}_${hostN}
fi

echo ; echo "Scene list: ${sceneList}" ; echo

# Loop over lines in List

while read -r line; do

    path_to_zip=$line
    
    logFile=$main_dir/ASTER/logs/aster_unzip_$(basename ${path_to_zip%.}).log

    echo ; echo "Start: $(date)" | tee $logFile
    echo "Logfile Name" ; echo $logFile
    echo "Preprocess: $path_to_zip" | tee -a $logFile
    cmd="preprocess_aster ${path_to_zip} ${main_dir}/ASTER/L1A ${batch_name} ${RM_DIR}"
    echo $cmd | tee -a $logFile
    eval $cmd
    echo "End: $(date)" | tee -a $logFile
    echo

done < ${sceneList}




