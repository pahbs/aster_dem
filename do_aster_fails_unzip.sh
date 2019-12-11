#!/bin/bash
#
# Read in a list of scenes (eg, list_2007_fails) that failed to process; remove the L1A/scene dir and redo the unzip
#    after this, run do_aster_stereo.sh on same list of scenes


################################
#_____Function Definitions_____
################################

join_by() { local IFS="$1"; shift; echo "$*"; }

preprocess_aster() {

    scenePath=$1
    to_dir=$2

    main_dir=$(dirname ${to_dir})

    rm -rf ${to_dir}/${sceneName}
    
    echo " ASTER scene is:"
    echo ${scenePath} 
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
            echo "Bad zip file. Write to list." 
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

    if [ ! -d "${to_dir}/${sceneName}" ]; then

        echo "[1] UNZIP SCENE..." 
        cmd="unzip -oj -d "${to_dir}/${sceneName}" ${to_dir}/$scene_zip"
        echo $cmd 

        # Handle bad unzip; write to list of bad zips
        if ! eval $cmd &> /dev/null; then
            echo "Bad zip file. Write to list."
            grep -qF "${scenePath}" "${main_dir}/list_bad_zips" || echo "$scenePath" >> "${main_dir}/list_bad_zips"
        else
            eval $cmd
            echo "$scene_zip"$'\r'
        fi

     else
        echo "Dir exists:" 
        echo "${sceneName}"
    fi
   
    rm -f ${to_dir}/$scene_zip
    rm -f ${to_dir}/${sceneName}/*.met
    rm -f ${to_dir}/${sceneName}/checksum_report 

}

#####################

batch=$1

topDir=/att/pubrepo/hma_data/ASTER
to_dir=$topDir/L1A

hostN=`/bin/hostname -s`
batchLogStem=${topDir}/logs/${batch}_${hostN}.log
cd $topDir

# Read in sceneList of AST L1A scenes (list_2007_fails)
while read -r scene; do
    sceneLog=${batchLogStem}_${sceneName}
    cd $topDir

	echo "Next scene:"
    echo $scene
    sceneName=$(basename $scene)

        scene_id=$(echo $sceneName| awk -F'_' '{print $3}')
        zip_path=$(find $topDir/L1A_orders -name *${scene_id}*.zip)      

    # Unzip the scene's zip file
    preprocess_aster $zip_path $to_dir | tee $sceneLog

done < ${batch}_${hostN}