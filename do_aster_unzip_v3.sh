#!/bin/bash
#
# [1] Download and unzip ASTER L1A data from earthdata.nasa.gov polygon searches
# [2] Create aster camera model
# [3] Mapproject
# [4] Footprint
## Check email for "LPDAAC ECS Order Notification Order ID: *****"
## ENTER THE PullDir NUMBER --> note, this is not the ORDERID or the REQUEST ID from the email
################################
#_____Function Definitions_____
################################

preprocess_aster() {

    scenePath=$1
    to_dir=$2
    logFile=$3
    main_dir=$(dirname ${to_dir})
    list_name=$main_dir/list_do_aster_stereo_${4}
    RM_DIR=$5

    echo " ASTER scene is:" | tee -a $logFile
    echo ${scenePath} | tee -a $logFile
    now="$(date +'%Y%m%d')"

    # Get scene name of scene zip
    cd ${to_dir}

    scene_zip=$(basename $scenePath)
    zip_dir=$(dirname $scenePath)

	if [[ $scene_zip == *"_L1A_"* ]]; then

	    # Copy the AST_L1A zip to the L1A dir
	    cmd="cp $scenePath ${to_dir}"
        # Handle bad copy; write to list of bad zips
        if ! eval $cmd &> /dev/null; then
            echo "Bad zip file. Write to list." | tee -a $logFile
            grep -qF "${scenePath}" "${main_dir}/list_bad_zips" || echo "$scenePath" >> "${main_dir}/list_bad_zips"
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
        rm -rf ${to_dir}/${sceneName}
    fi

    if [ ! -d "${to_dir}/${sceneName}" ]; then

        echo "[1] UNZIP SCENE..." | tee -a $logFile
        cmd="unzip -oj -d "${to_dir}/${sceneName}" ${to_dir}/$scene_zip"
        echo $cmd | tee -a $logFile

        # Handle bad unzip; write to list of bad zips
        if ! eval $cmd &> /dev/null; then
            echo "Bad zip file. Write to list." | tee -a $logFile
            grep -qF "${scenePath}" "${main_dir}/list_bad_zips" || echo "$scenePath" >> "${main_dir}/list_bad_zips"
        else
            eval $cmd
            echo "$scene_zip"$'\r' | tee -a $logFile
            echo "Removing all but Band3 data" | tee -a $logFile
            rm ${to_dir}/${sceneName}/*Band[12456789]*
            rm ${to_dir}/${sceneName}/*Supplement*
        fi

        echo "[2] CREATE CAMERA MODEL ..." | tee -a $logFile
        echo "${sceneName}" | tee -a $logFile

        if [ -f "${to_dir}/${sceneName}/in-Band3N.tif" ]; then
            echo "ASP input files exists already." | tee -a $logFile
        else
            echo "Running aster2asp on $sceneName ..."$'\r' | tee -a $logFile
            aster2asp --threads=15 ${to_dir}/${sceneName} -o ${to_dir}/${sceneName}/in

            if [ -f "${to_dir}/${sceneName}/in-Band3N.tif" ] && [ -f "${to_dir}/${sceneName}/in-Band3B.tif" ] ; then
                # Add sceneName to an order list to feed into do_aster_stere.sh
                echo "Add $sceneName to $list_name .." | tee -a $logFile
                grep -qF "${sceneName}" "$list_name" || echo "$sceneName" >> "$list_name"
            fi
        fi

    else
        echo "Dir exists:" | tee -a $logFile
        echo "${sceneName}" | tee -a $logFile
    fi
   
    rm -f ${to_dir}/$scene_zip
    rm -f ${to_dir}/${sceneName}/*.met
    rm -f ${to_dir}/${sceneName}/checksum_report 

}


join_by() { local IFS="$1"; shift; echo "$*"; }

################################
#
# VARIABLES FOR RUN
#
# Launch like this example:
# pupsh "hostname ~ 'ecotone01'" "do_aster_unzip_v3.sh /att/pubrepo/hma_data/ASTER/L1A_orders/2017/list_scenes_zip batch2017 /att/pubrepo/hma_data/ASTER/L1A true"
# pupsh "hostname ~ 'ecotone10'" "do_aster_unzip_v3.sh /att/nobackup/pmontesa/userfs02/ASTER/L1A_orders/boreal/scenes.zip.list batch_sib /att/nobackup/pmontesa/userfs02/ASTER/L1A true"

# required args
sceneList=$1                            # /path/to/main/zip_list
batch_name=$2                           # Creates a list 4 stereo (a main batch list of scenenames); can be subdivided and processed on VMs with do_aster_stereo.sh

to_dir=${3:-'/att/nobackup/pmontesa/data/ASTER/L1A'} # probably the L1A dir (full path)
RM_DIR=${4:-'false'}                    # Remove existing scene dirs and unzip, redo-ing all processing for this list of zips? 

mkdir -p $to_dir
mkdir -p $(dirname ${to_dir})/logs

# Get hostname
hostN=`/bin/hostname -s`

echo ${sceneList}_${hostN}

# Loop over lines in List

while read -r line; do

    path_to_zip=$line
    
    logFile=$(dirname ${to_dir})/logs/aster_unzip_$(basename ${path_to_zip%.}).log
    
    echo "Start: $(date)" | tee $logFile
    echo "Preprocess: $path_to_zip" | tee -a $logFile
    preprocess_aster $path_to_zip $to_dir $logFile $batch_name $RM_DIR
    echo "End: $(date)" | tee -a $logFile
    
done < ${sceneList}_${hostN}




