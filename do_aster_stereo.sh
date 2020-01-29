#!/bin/bash
#
# Process ASTER L1A scene-level .zip files data from earthdata.nasa.gov polygon searches
#   (eg; AST_L1A_00306232003135434_20170125151451_24922.zip)
#
# Example of most recent call:
# pupsh "hostname ~ 'ecotone|crane'" "do_aster_stereo.sh list_do_aster_stereo_batch_colima 30 $NOBACKUP/userfs02/data $NOBACKUP/userfs02/refdem/TDM1_DEM__30_N19W104_DEM.tif hardlink true true true true 3 3 49 0"
#
# Get a refdem from TDX90m
# cd $NOBACKUP/userfs02/data/tandemx
# gdalbuildvrt $NOBACKUP/userfs02/refdem/TDM1_DEM__30_fairbanks_DEM.vrt $PWD/TDM90/TDM1_DEM__30_N6[3456]W1[45]*/DEM/*DEM.tif
# gdal_translate $NOBACKUP/userfs02/refdem/TDM1_DEM__30_fairbanks_DEM.vrt /att/nobackup/pmontesa/userfs02/refdem/TDM1_DEM__30_fairbanks_DEM.tif

# Reference DEMs
# $NOBACKUP/userfs02/refdem/ASTGTM2_N40-79.vrt
# $NOBACKUP/userfs02/data/tandemx/TDM90/mos/TDM1_DEM_90m_DEM.vrt
# /att/pubrepo/hma_data/products/nasadem/hma_nasadem_hgt_merge_hgt_aea.tif

################################
#_____Function Definitions_____
################################

run_mapprj() {

    # Note:
    # The purporse of mapprojecting input stereopairs is to speed up the alignment at the 'preprocessing' stage of stereo.
    # Make sure you have a reference DEM in a projection that is appropriate for the area of the input data.
    # Otherwise, the mapprojected files will be much larger that in original data, and significantly lengthen the alignment.

    inDEM=${1}
    sceneName=${2}
    threads_per=${3}

    cmd_list=''
    echo "Running mapproject ..." 
    for type in N B ; do
        cmd=''
        cmd+="mapproject --threads=$threads_per $inDEM $sceneName/in-Band3${type}.tif $sceneName/in-Band3${type}.xml $sceneName/in-Band3${type}_proj.tif ; "
        echo $cmd
        cmd_list+=\ \'$cmd\'
    done

    eval parallel --delay 2 -verbose -j 2 ::: $cmd_list

    echo "Finished mapprojecting" 
}

run_asp() {

    MAP=$1
    SGM=$2
    inDEM=$3
    tileSize=$4
    sceneName=$5
    ##now=$6
    L1Adir=$6
    logFile=$7

    med_filt_sz=${8:-'0'}
    text_smth_sz=${9:-'0'}
    erode_max_sz=${10:-'0'}
    erode_len=${11:-'0'}
    res=${12}
    LINK=${13}

    echo; echo "L1A dir: $L1Adir"; echo  
    cd $L1Adir

    sgm_corrKern=7
    ncc_corrKern=21
    subpixKern=21

    # Get # of THREADs (aka siblings aka logical cores) per CORE
    nthread_core=$(lscpu | awk '/^Thread/ {threads=$NF} END {print threads}')
    # Get # of COREs per CPU
    ncore_cpu=$(lscpu | awk '/^Core/ {cores=$NF} END {print cores}')
    # Get # of CPUs (aka sockets)
    ncpu=$(lscpu | awk '/^Socket.s.:/ {sockets=$NF} END {print sockets}')
    # Get # of logical cores
    nlogical_cores=$((nthread_core * ncore_cpu * ncpu ))

    #runDir=corr${corrKern}_subpix${subpixKern}
	echo
    echo "Working on: $sceneName "
    echo "Input coarse DEM: ${inDEM}" 

    outPrefix=$L1Adir/$sceneName/outASP/out

    # Stereo Run Options
    #
    # parallel_stereo with SGM
    par_opts="--corr-tile-size $tileSize --job-size-w $tileSize --job-size-h $tileSize"
    par_opts+=" --processes $nlogical_cores --threads-multiprocess 1 --threads-singleprocess $nlogical_cores"

    sgm_opts="-t aster --xcorr-threshold -1 --corr-kernel $sgm_corrKern $sgm_corrKern"
    sgm_opts+=" --erode-max-size $erode_max_sz --cost-mode 4 --subpixel-mode 0 --median-filter-size $med_filt_sz --texture-smooth-size $text_smth_sz --texture-smooth-scale 0.13"
    
    ncc_opts="-t aster --cost-mode 2 --corr-kernel $ncc_corrKern $ncc_corrKern --subpixel-mode 2 --subpixel-kernel $subpixKern $subpixKern"
    
    in_nadir=$sceneName/in-Band3N.tif
    in_back=$sceneName/in-Band3B.tif
    
    echo ; echo "Check for stereopair input" 
    inPre=$sceneName/in-Band3

    if gdalinfo ${inPre}N.tif >> /dev/null && gdalinfo ${inPre}B.tif >> /dev/null && [ -f ${inPre}N.xml ] && [ -f ${inPre}B.xml ]; then
        echo ; echo "[1] Stereopair input exists." 
    else
		echo "[1] Running aster2asp on $sceneName ..."
		echo ; find $sceneName -type f -name in-Band3* -exec rm -rf {} \;

        cmd="aster2asp --threads=$nlogical_cores ${sceneName} -o ${sceneName}/in"
        echo $cmd ; eval $cmd
    fi

    cmd_maprj="run_mapprj $inDEM $sceneName $(($nlogical_cores / 2))"

    if [ "$MAP" = true ] ; then
        if [ ! -f ${inPre}N_proj.tif ] || [ ! -f ${inPre}B_proj.tif ] ; then

            echo ; echo "[2] Running mapproject..."
            find $sceneName -type f -name in-Band3*_proj.tif -exec rm -rf {} \;
            echo $cmd_maprj ; eval $cmd_maprj
        fi
        if gdalinfo ${inPre}N_proj.tif >> /dev/null && gdalinfo ${inPre}B_proj.tif >> /dev/null ; then
            echo ; echo "[2] Mapproject already complete."
        else
            echo ; echo "[2] Mapproject re-do..."
            find $sceneName -type f -name in-Band3*_proj.tif -exec rm -rf {} \;
            echo $cmd_maprj ; eval $cmd_maprj
        fi
    fi

    if [ "$MAP" = true ] ; then
        echo ; echo "Using mapprojected input stereopairs." 
        in_nadir=${in_nadir%.*}_proj.tif
        in_back=${in_back%.*}_proj.tif
    fi

    echo ; echo "Size of input nadir image: $(gdalinfo $in_nadir | grep 'Size')" 
    
    # Set the args for stereo after determining if stereopairs will be mapprojected
    stereo_args="$in_nadir $in_back $sceneName/in-Band3N.xml $sceneName/in-Band3B.xml $outPrefix"

    if [ "$MAP" = true ] ; then
        stereo_args+=" $inDEM"
    fi

    echo; echo "outPrefix PC: $outPrefix-PC.tif"; echo

    if [ ! -f $outPrefix-PC.tif ]; then

        echo "[3] Run AMES Stereo Pipeline stereogrammetry..."
        echo "Determine which stereo algorithm to run ..."
        echo "Tile size = ${tileSize}"

        if [ "$SGM" = true ] ; then

            echo "Running SGM stereo algorithm"

            find $sceneName/outASP -type f -name out* -exec rm -rf {} \;

            cmd="parallel_stereo --stereo-algorithm 1 $par_opts $sgm_opts $stereo_args"
            #cmd="stereo --stereo-algorithm 1 --corr-tile-size 10000 --threads $ncpu $sgm_opts $stereo_args"
            echo ; echo $cmd ; eval $cmd
            echo "Finished stereo from SGM mode."

            if [ ! -f $outPrefix-PC.tif ]; then

                echo "Running MGM stereo algorithm(SGM failed to create a PC.tif) ..."

                find $sceneName/outASP -type f -name out* -exec rm -rf {} \;
                cmd="parallel_stereo --stereo-algorithm 2 $par_opts $sgm_opts $stereo_args"
                #cmd="stereo --stereo-algorithm 2 --corr-tile-size 10000 --threads $ncpu $sgm_opts $stereo_args"
                echo ; echo $cmd ; eval $cmd
                echo "Finished stereo from MGM mode."
            fi

            if [ -f $outPrefix-PC.tif ]; then
			    echo "Stereo successful from SGM or MGM mode."
            else
			    echo "Stereo NOT successful from SGM or MGM mode." 
            fi
        fi

        # If SGM is false or fails, this is the stereo that is attempted
        if [ "$SGM" = false ] || [ ! -f $outPrefix-PC.tif ] ; then

            echo "Running stereo with local search window algorithm ..."
            #cmd="parallel_stereo $par_opts $ncc_opts $stereo_args"
            cmd="stereo --threads $ncpu $ncc_opts $stereo_args"
            echo ; echo $cmd ; eval $cmd
            echo "Finished stereo."
        fi
    else
        echo "[3] Stereo complete. PC file exists."
    fi

    if gdalinfo ${outPrefix}-PC.tif | grep -q VRT ; then

        echo "Convert PC.tif from virtual to real"
        eval time gdal_translate $gdal_opts ${outPrefix}-PC.tif ${outPrefix}-PC_full.tif
        mv ${outPrefix}-PC_full.tif ${outPrefix}-PC.tif

        echo "Removing intermediate parallel_stereo dirs"
        rm -rf ${outPrefix}*/
        rm -f ${outPrefix}-log-stereo_parse*.txt
    fi

    if [ -f "${outPrefix}-PC.tif" ] ; then
    
        echo "[4] Ready to run do_aster_p2d.sh"
        cmd="do_aster_p2d.sh ${sceneName} ${L1Adir} ${erode_len} ${res} ${inDEM} ${LINK}"
        echo ; echo $cmd ; eval $cmd

        if [ -e $outPrefix-DEM_cr.tif ] ; then  
            echo "[END] Finished processing ${sceneName}."
        else
            echo "[END] Finished processing ${sceneName}. DEM not created."
        fi
    fi
    if [ ! -e $outPrefix-PC.tif ] ; then
        echo "[END] Finished processing ${sceneName}. No PC.tif file. DEM not created."
    fi

    for i in F L R RD D GoodPixelMap lMask rMask lMask_sub rMask_sub L_sub R_sub D_sub ; do
        if [ -e $outPrefix-${i}.tif ]; then
            rm -v $outPrefix-${i}.tif
        fi
    done
}
##############################################
#
# Main portion of script
#
# A main list of scenes (that has a sub-lists specific to the set of VMs youll use)
# If not running across sub-lists that are already named with the VM, then rename your list like this:
# <your_list>_<VMname> (eg, batch_colima_wetf101)

t_start=$(date +%s)

batch=$1

# Output resolution of DEM
res_dem=${2:-'30'}

# Indicate main dir into which ASTER subdir will be placed
dir_ASTER=${3}/ASTER

# Input reference DEM with no holes for mapproject and cloud-removal
inDEM=${4}

# Use 'hardlink' to copy output DEMs to common dir (gets passed to do_aster_p2d.sh)
LINK=${5:-'symlink'}

# Do mapproject: true or false
MAP=${6:-'true'}

# Re-do mapproject: true or false
REDO_MAP=${7:-'true'}

# Re-do stereo: true or false
REDO_STEREO=${8:-'true'}

# Use Semi-Global Matching stereo algorithm?
SGM=${9:-'true'}

# Smallest filter windows for smoothing are the defaults
med_filt_sz=${10:-'3'}
text_smth_sz=${11:-'3'}

# Remove isolated groups of pixels of this size or smaller during stereo_fltr
erode_max_sz=${12:-'0'}

# Erode point cloud at boundaries with nodata by this many pixels
erode_len=${13:-'0'}

# Job tile size for SGM run; tilesize^2 * 300 / 1e9 = RAM needed per thread
tileSize=${14:-'1024'}

# For testing
TEST_DIR_TAIL=${15:-''}

#num_min_old=60
num_old=0.1 #days
hostN=`/bin/hostname -s`
mkdir -p $dir_ASTER
out_dir=$dir_ASTER/L1A${TEST_DIR_TAIL}
mkdir -p $out_dir

##now="$(date +'%Y%m%d%T')"

# Process the AST_L1A dir indicated with the sceneName

cd $dir_ASTER

mkdir -p $dir_ASTER/logs
batchLogStem=$dir_ASTER/logs/${batch}_${hostN}

cnt_tmpfile=/tmp/$$.tmp
echo 0 > $cnt_tmpfile

# Read in sceneList of AST L1A scenes
while read -r scene; do

    cd $dir_ASTER

	echo "Next scene: $scene"
    sceneName=$(basename $scene)

    sceneLog=${batchLogStem}_${sceneName}.log

    echo; echo "START: Script call at $(date)" | tee -a $sceneLog
    echo "${0} ${1} ${2} ${3} ${4} ${5} ${6} ${7} ${8} ${9} ${10} ${11} ${12} ${13} ${14}" | tee -a $sceneLog
    echo "Scene name: ${sceneName}" | tee -a $sceneLog

	if [ -d "${out_dir}/${sceneName}" ]; then 
		
        if [[ "$MAP" = true ]] && [[ "$REDO_MAP" = true ]] ; then
            # Delete if files older than (indicated with '+') num_old; use '-' to indicate 'younger than'
            find ${out_dir}/${sceneName}/in-Band*proj.tif -mtime +${num_old} -exec rm {} \;
        fi

        if [ "$REDO_STEREO" = true ] ; then

            echo ; echo "Deleting PC file!" ; echo
            rm -rfv ${out_dir}/${sceneName}/outASP/out-PC.tif

            ### Delete if files older than (indicated with '+') num_old; use '-' to indicate 'younger than'
            ##find ${out_dir}/${sceneName}/outASP/out-PC.tif -mtime +${num_old} -exec rm {} \;
            
            if [ ! -e "${out_dir}/${sceneName}/outASP/out-PC.tif" ] ; then
                echo; echo "PC and DEM deleted b/c it was older than ${num_old} days . Re-do stereo" ; echo | tee -a $sceneLog
                rm -rfv ${out_dir}/${sceneName}/outASP/out-DEM*.tif
            else
                echo ; echo "PC file is newer than ${num_old} days. Keep it."; echo | tee -a $sceneLog
            fi
           
        fi

		echo ; echo "Running ASP routines..." | tee -a $sceneLog
        
        # Look above for function arg descriptions
    	cmd="run_asp $MAP $SGM $inDEM $tileSize $sceneName $out_dir $sceneLog $med_filt_sz $text_smth_sz $erode_max_sz $erode_len $res_dem $LINK"
        echo ; echo $cmd ; eval $cmd
	
    else
		echo "Delete tmp ASP files..."
		find $out_dir/$sceneName/outASP -type f -name "out*.tif" ! -name "out-PC.tif" ! -name "out-DEM*" ! -name "out-DRG*" ! -name "out-L.tif" ! -name "out-F.tif" -exec rm -rf {} \;
	fi

	echo "Delete zip: $out_dir/${sceneName}.zip" | tee -a $sceneLog
	rm -rf $out_dir/${sceneName}.zip
    echo "END: $(date)" | tee -a $sceneLog

done < ${batch}_${hostN}

t_end=$(date +%s)
t_diff=$(expr "$t_end" - "$t_start")
t_diff_hr=$(printf "%0.4f" $(echo "$t_diff/3600" | bc -l ))

echo; date
echo "Total processing time for pair ${pairname} in hrs: ${t_diff_hr}"


echo; echo "When all scenes are processed, footprint the cloud-removed DSMs: run_foot_raster.sh ASTER $dir_ASTER/L1A_out/cr/dsm" ; echo
exit 1