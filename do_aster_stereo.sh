#!/bin/bash
#
# Process ASTER L1A scene-level .zip files data from earthdata.nasa.gov polygon searches
#   (eg; AST_L1A_00306232003135434_20170125151451_24922.zip)
#
# Example of most recent call:
# pupsh "hostname ~ 'ecotone01'" "do_aster_stereo.sh list_2017 true true true 3 3 49 2"
# pupsh "hostname ~ 'wetf101'" "do_aster_stereo.sh batch_colima true true true true 3 3 49 2 30 <path_to_ref_DEM> /att/nobackup/<usr>/data/ASTER"

################################
#_____Function Definitions_____
################################


run_mapprj() {

    inDEM=$1
    sceneName=$2
    logFile=$3

    cmd_list=''
    echo "Running mapproject ..." | tee -a $logFile
    for type in N B ; do
        cmd=''
        cmd+="mapproject --threads=5 $inDEM $sceneName/in-Band3${type}.tif $sceneName/in-Band3${type}.xml $sceneName/in-Band3${type}_proj.tif ; "
        echo $cmd
        cmd_list+=\ \'$cmd\'
    done

    eval parallel --delay 2 -verbose -j 2 ::: $cmd_list

    echo "Finished mapprojecting" | tee -a $logFile
}

run_asp() {

    MAP=$1
    SGM=$2
    inDEM=$3
    tileSize=$4
    sceneName=$5
    now=$6
    L1Adir=$7
    logFile=$8

    med_filt_sz=${9}
    text_smth_sz=${10}
    erode_max_sz=${11}
    erode_len=${12}
    res=${13}
    
    if [ "${med_filt_sz}" = "" ] || [ "${text_smth_sz}" = "" ]  ; then
        # The length of 1 of the strings is zero, so set both to default
        med_filt_sz=0
        text_smth_sz=0
    fi
    if [ "${erode_max_sz}" = "" ] ; then
        erode_max_sz=0
    fi
    echo; echo "L1A dir: $L1Adir"; echo  | tee -a $logFile
    cd $L1Adir

    sgm_corrKern=7
    ncc_corrKern=21
    subpixKern=21

    ncpu=$(cat /proc/cpuinfo | egrep "core id|physical id" | tr -d "\n" | sed s/physical/\\nphysical/g | grep -v ^$ | sort | uniq | wc -l)

    #runDir=corr${corrKern}_subpix${subpixKern}
	echo " " | tee -a $logFile
    echo "Working on: $sceneName " | tee -a $logFile
    echo "Input coarse DEM: ${inDEM}" | tee -a $logFile

    outPrefix=$L1Adir/$sceneName/outASP/out

    # Stereo Run Options
    #
    # parallel_stereo with SGM
    par_opts="--corr-tile-size $tileSize --job-size-w $tileSize --job-size-h $tileSize"
    par_opts+=" --processes 16 --threads-multiprocess 1 --threads-singleprocess $ncpu"

    sgm_opts="-t aster --xcorr-threshold -1 --corr-kernel $sgm_corrKern $sgm_corrKern"
    sgm_opts+=" --erode-max-size $erode_max_sz --cost-mode 4 --subpixel-mode 0 --median-filter-size $med_filt_sz --texture-smooth-size $text_smth_sz --texture-smooth-scale 0.13"
    
    ncc_opts="-t aster --cost-mode 2 --corr-kernel $ncc_corrKern $ncc_corrKern --subpixel-mode 2 --subpixel-kernel $subpixKern $subpixKern"
    
    if [ "$MAP" = true ] ; then
        stereo_args="$sceneName/in-Band3N_proj.tif $sceneName/in-Band3B_proj.tif $sceneName/in-Band3N.xml $sceneName/in-Band3B.xml $outPrefix $inDEM"
    else
        stereo_args="$sceneName/in-Band3N.tif $sceneName/in-Band3B.tif $sceneName/in-Band3N.xml $sceneName/in-Band3B.xml $outPrefix"
    fi

    echo "Check for ASP input" | tee -a $logFile
    inPre=$sceneName/in-Band3

    if gdalinfo ${inPre}N.tif >> /dev/null && gdalinfo ${inPre}B.tif >> /dev/null && [ -f ${inPre}N.xml ] && [ -f ${inPre}B.xml ]; then
        echo "[1] ASP input exists." | tee -a $logFile
    else
		echo "[1] Running aster2asp on $sceneName ..." | tee -a $logFile
		find $sceneName -type f -name in-Band3* -exec rm -rf {} \;

        cmd="aster2asp --threads=15 ${sceneName} -o ${sceneName}/in"
        echo $cmd | tee -a $logFile
        eval $cmd
    fi

    if [ "$MAP" = true ] ; then
        if [ ! -f ${inPre}N_proj.tif ] || [ ! -f ${inPre}B_proj.tif ] ; then

            echo "[2] Running ASP Mapproject..." | tee -a $logfile
            find $sceneName -type f -name in-Band3*_proj.tif -exec rm -rf {} \;

            cmd="run_mapprj $inDEM $sceneName $logFile"
            echo $cmd
            eval $cmd

        fi

        if gdalinfo ${inPre}N_proj.tif >> /dev/null && gdalinfo ${inPre}B_proj.tif >> /dev/null ; then
            echo "[2] ASP Mapproject already complete." | tee -a $logFile
        else
            echo "[2] ASP Mapproject re-do..." | tee -a $logFile
            find $sceneName -type f -name in-Band3*_proj.tif -exec rm -rf {} \;

            cmd="run_mapprj $inDEM $sceneName $logFile"
            echo $cmd
            eval $cmd
        fi
    fi

    echo; echo "outPrefix PC: $outPrefix-PC.tif"; echo

    if [ ! -f $outPrefix-PC.tif ]; then
        echo "[3] Run ASP stereo with the map-projected images..." | tee -a $logFile
        echo "Determine which stereo algorithm to run ..." | tee -a $logFile
        echo "Tile size = ${tileSize}" | tee -a $logFile

        if [ "$SGM" = true ] ; then

            echo "Running SGM stereo algorithm" | tee -a $logFile

            find $sceneName/outASP -type f -name out* -exec rm -rf {} \;

            cmd="parallel_stereo --stereo-algorithm 1 $par_opts $sgm_opts $stereo_args"
            #cmd="stereo --stereo-algorithm 1 --corr-tile-size 10000 --threads $ncpu $sgm_opts $stereo_args"
            echo $cmd | tee -a $logFile
            eval $cmd
            echo "Finished stereo from SGM mode." | tee -a $logFile

            if [ ! -f $outPrefix-PC.tif ]; then

                echo "Running MGM stereo algorithm(SGM failed to create a PC.tif) ..." | tee -a $logFile

                find $sceneName/outASP -type f -name out* -exec rm -rf {} \;
                cmd="parallel_stereo --stereo-algorithm 2 $par_opts $sgm_opts $stereo_args"
                #cmd="stereo --stereo-algorithm 2 --corr-tile-size 10000 --threads $ncpu $sgm_opts $stereo_args"
                echo $cmd | tee -a $logFile
                eval $cmd
                echo "Finished stereo from MGM mode." | tee -a $logFile
            fi

            if [ -f $outPrefix-PC.tif ]; then
					echo "Stereo successful from SGM or MGM mode." | tee -a $logFile
				else
					echo "Stereo NOT successful from SGM or MGM mode." | tee -a $logFile
            fi
        fi

        # If SGM is false or fails, this is the stereo that is attempted
        if [ "$SGM" = false ] || [ ! -f $outPrefix-PC.tif ] ; then

            echo "Running stereo with local search window algorithm ..." | tee -a $logFile
            #cmd="parallel_stereo $par_opts $ncc_opts $stereo_args"
            cmd="stereo --threads $ncpu $ncc_opts $stereo_args"
            echo $cmd | tee -a $logFile
            eval $cmd
            echo "Finished stereo." | tee -a $logFile
        fi
    else
        echo "[3] Stereo complete. PC file exists." | tee -a $logFile
    fi

    if gdalinfo ${outPrefix}-PC.tif | grep -q VRT ; then
        echo "Convert PC.tif from virtual to real" | tee -a $logFile
        eval time gdal_translate $gdal_opts ${outPrefix}-PC.tif ${outPrefix}-PC_full.tif
        mv ${outPrefix}-PC_full.tif ${outPrefix}-PC.tif
        echo "Removing intermediate parallel_stereo dirs" | tee -a $logFile
        rm -rf ${outPrefix}*/
        rm -f ${outPrefix}-log-stereo_parse*.txt
    fi

    if [ -f "${outPrefix}-PC.tif" ] ; then
    
        echo "[4] Ready to run do_aster_p2d.sh" | tee -a $logFile
        cmd=""
        cmd="do_aster_p2d.sh ${sceneName} ${L1Adir} ${erode_len} ${res} ${inDEM}"
        echo $cmd
        eval $cmd | tee -a $logFile

        if [ -e $outPrefix-DEM_cr.tif ] ; then  
            echo "[END] Finished processing ${sceneName}." | tee -a $logFile
        else
            echo "[END] Finished processing ${sceneName}. DEM not created." | tee -a $logFile
        fi
    fi
    if [ ! -e $outPrefix-PC.tif ] ; then
        echo "[END] Finished processing ${sceneName}. No PC.tif file. DEM not created." | tee -a $logFile
    fi

    for i in F L R RD D GoodPixelMap lMask rMask lMask_sub rMask_sub L_sub R_sub D_sub ; do
        if [ -e $outPrefix-${i}.tif ]; then
            rm -v $outPrefix-${i}.tif
        fi
    done
}
##############################################
#
# Hard coded stuff
#

# A main list of scenes (that has a sub-lists specific to the set of VMs youll use)
# If not running across sub-lists that are already named with the VM, then reanme your list like this: <your_list>_<VMname> (eg, batch_colima_wetf101)
batch=$1

# true or false
MAP=${2:-'true'}
# true or false
REDO_MAP=${3:-'true'}
# true or false
REDO_STEREO=${4:-'true'}
# Use Semi-Global Matching stereo algorithm?
SGM=${5:-'true'}

# Smallest filter windows for smoothing are the defaults
med_filt_sz=${6:-'3'}
text_smth_sz=${7:-'3'}

# Try to find a value that removes pixels adjacent to NoData that may be more likley to be bad. This can be done at two different stages:
# first stage: stereo
erode_max_sz=$8
# second stage: point2dem
erode_len=$9

# Output resolution of DEM
res=${10:-'30'}	#30m for HMA

# Input DEM for mapproject and cloud-removal
#inDEM=/att/pubrepo/hma_data/products/nasadem/hma_nasadem_hgt_merge_hgt_aea.tif
#inDEM=/att/gpfsfs/briskfs01/ppl/pmontesa/userfs02/refdem/ASTGTM2_N40-79E.vrt
#inDEM=/att/gpfsfs/briskfs01/ppl/pmontesa/userfs02/refdem/siberia/SIB_ASTGTM2_pct100.tif
inDEM=${11}

topDir=${12} #/att/pubrepo/hma_data/ASTER

hostN=`/bin/hostname -s`

# Job tile size for SGM run; tilesize^2 * 300 / 1e9 = RAM needed per thread
tileSize=5000 #1024

TEST_DIR_TAIL=${13:-''}

#num_min_old=60
num_old=5 #days

out_dir=$topDir/L1A${TEST_DIR_TAIL}
mkdir -p $out_dir

now="$(date +'%Y%m%d%T')"

# Process the AST_L1A dir indicated with the sceneName

cd $topDir

batchLogStem=${topDir}/logs/${batch}_${hostN}.log

cnt_tmpfile=/tmp/$$.tmp
echo 0 > $cnt_tmpfile

# Read in sceneList of AST L1A scenes
while read -r scene; do

    cd $topDir

	echo "Next scene:"
    echo $scene
    sceneName=$(basename $scene)

    sceneLog=${batchLogStem}_${sceneName}
    echo "Scene name: ${sceneName}" | tee -a $sceneLog
    echo "START: $(date)" | tee -a $sceneLog 

	if [ -d "${out_dir}/${sceneName}" ]; then 
		
        if [ "$MAP" = true ] && [ "$REDO_MAP" = true ] ; then
            # Delete if files older than (indicated with '+') num_old; use '-' to indicate 'younger than'
            find ${out_dir}/${sceneName}/in-Band*proj.tif -mtime +${num_old} -exec rm {} \;
        fi

        if [ "$REDO_STEREO" = true ] ; then

            # Delete if files older than (indicated with '+') num_old; use '-' to indicate 'younger than'
            find ${out_dir}/${sceneName}/outASP/out-PC.tif -mtime +${num_old} -exec rm {} \;
            
            if [ ! -e "${out_dir}/${sceneName}/outASP/out-PC.tif" ] ; then
                echo; echo "PC and DEM deleted b/c it was older than ${num_old} days . Re-do stereo"; echo | tee -a $logFile
                rm -rfv ${out_dir}/${sceneName}/outASP/out-DEM*.tif
            else
                echo; echo "PC file is newer than ${num_old} days. Keep it."; echo | tee -a $logFile
            fi
           
        fi

        #Function call
		echo "Running ASP routines..." | tee -a $sceneLog
        # Args: sgm t/f, DEM for mapprj, tile sz for SGM, sceneName, time, out_dir, log, a stereo param, a stereo param, a stereo param, a p2d param
    	run_asp $MAP $SGM $inDEM $tileSize $sceneName $now $out_dir $sceneLog $med_filt_sz $text_smth_sz $erode_max_sz $erode_len $res
	
    else
		echo "Delete tmp ASP files..."
		find $out_dir/$sceneName/outASP -type f -name "out*.tif" ! -name "out-PC.tif" ! -name "out-DEM*" ! -name "out-DRG*" ! -name "out-L.tif" ! -name "out-F.tif" -exec rm -rf {} \;
	fi

	echo "Delete zip: $out_dir/${sceneName}.zip" | tee -a $sceneLog
	rm -rf $out_dir/${sceneName}.zip
    echo "END: $(date)" | tee -a $sceneLog

done < ${batch}_${hostN}



