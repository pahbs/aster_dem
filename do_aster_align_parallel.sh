#!/bin/bash

# Created on Thu Jan 23 2020
# @author: emacorps
# Performs dem_align.py on the ASTER Cloud Removed DEMs generated from do_aster_stereo and pts2grid
# Uses "dem_align_wmask.py" which is a modified version of dem_align from D. Shean
# The modified version calls for a shapefile with polygons over non-static surfaces

# Example of last call:
# do_aster_align.sh /att/nobackup/emacorps/data/ASTER/Colima_L1A_out/cr/dsm_test /att/nobackup/emacorps/data/ASTER/TDM1_DEM__30_N19W104_DEM_masked_erode.tif /att/nobackup/emacorps/data/ASTER/non_static_surface.shp 32613 '' '' 2 '' '' '' '' '' 5

# pupsh "hostname ~ 'ecotone'" "do_aster_align.sh /att/gpfsfs/briskfs01/ppl/pmontesa/userfs02/data/ASTER/L1A_out/cr/list_DEM_cr /att/gpfsfs/briskfs01/ppl/pmontesa/userfs02/data/tandemx/subset_fareast/TDM90/mos/TDM1_DEM_90m_circ_DEM_masked_E_laea.tif /att/gpfsfs/briskfs01/ppl/pmontesa/userfs02/projects/misc/proposal_roses2020_lcluc/TDX_static_control_surfaces.shp

##################################
# ____Main portion of script____ #
##################################
source ~/anaconda3/bin/activate demenv

t_start=$(date +%s)

# A VM-specific list
# The main scenes list for which sublists have been made with gen_chunks.py
# this list is adjacent to DSM dir
DSMlist=$1

# Input directory of cloud-removed DSM folder
DSMdir=$(dirname ${DSMlist})/dsm

# Input files
ref_fn=$2 # Reference DEM filename
mask=${3:-'None'} # Non-static surfaces mask shapefile

# dem_align processing options
mode=${4:-'nuth'}

tiltcorr=${5:-'true'} # type = action:  After preliminary translation, fit 2D polynomial to residual elevation offsets and remove (default: False if not in parameter list as -tiltcorr) # if true: tiltcorr='-tiltcorr'

polyorder=${6:-'1'} #type = int

tol=${7:-'0.02'} #type = float

max_offset=${8:-'100'} # type = float

max_dz=${9:-'100'} # type = float

res=${10:-'mean'}

slope_lim=${11:-'0.1 40'} # type = float

max_iter=${12:-'30'} # type = int

RM_DIR=${13:-'true'} # if True: Remove all auxiliary files

# Get Main path to DSM folder as topDir
topDir=$(dirname ${DSMdir}) #e.g. /att/nobackup/emacorps/data/ASTER/L1A_orders/colima/L1A_out/cr
echo "Top directory: $topDir"

# Create the final output folder in topDir in which only aligned dsm will be stored
out_dir=${topDir}/dsm_align
mkdir -p $out_dir
# Get VM hostname
hostN=`/bin/hostname -s`

# Create log file to record everything happenning during processing and store in output directory
logFile=${out_dir}/${hostN}_MainLog.log
echo "Processing steps logged in main log file: $logFile"
echo -e "input parameters: \nDSMdir: $DSMdir \nRef DEM: $ref_fn \nMask Shapefile: $mask \nEPSG: $epsg \nWith Processing Options: \n-mode: $mode \n-tiltcorr: $tiltcorr \n-polyorder: $polyorder \n-tol: $tol \n-max_offset: $max_offset \n-max_dz: $max_dz \n-res: $res \n-slope: $slope_lim \n-max_iter: $max_iter \nRemove auxiliary files: $RM_DIR \n" | tee -a $logFile
echo -e "INITIALIZING PROCESSING... \nScript call at: $(date)" | tee -a $logFile

#echo "Reprojecting $ref_fn to AEA projection" | tee -a $logFile
#ref_fn_aea=${out_dir}/Ref_DEM_AEA.tif
#echo "Reprojected reference DEM: $ref_fn_aea" | tee -a $logFile
#cmd="gdalwarp -of GTiff -t_srs '+proj=aea +lat_1=25 +lat_2=47 +lat_0=36 +lon_0=85 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs ' $ref_fn $ref_fn_aea"
#echo; echo $cmd; eval $cmd

if [ -s "$mask" ]; then
    echo "Reprojecting $mask to AEA projection" | tee -a $logFile
    mask_aea=${out_dir}/mask_shp_AEA.shp
    echo "Reprojected mask shapefile: $mask_aea" | tee -a $logFile
    cmd="ogr2ogr -t_srs '+proj=aea +lat_1=25 +lat_2=47 +lat_0=36 +lon_0=85 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs ' $mask_aea $mask"
    echo; echo $cmd; eval $cmd
fi

echo "Beginning Coregistration & Alignment Process..." | tee -a $logFile
echo "Processing directory: $DSMdir" | tee -a $logFile
if [ -s "$mask" ]; then
    echo "Aligning each cloud-removed scenes to Reference DEM $ref_fn_aea using mask $mask_aea" | tee -a $logFile
else
    echo "Aligning each cloud-removed scenes to Reference DEM $ref_fn_aea without mask" | tee -a $logFile
fi

cd $topDir

# VM name
hostN=`/bin/hostname -s`

# The list name for a given VM that will run its list of files in parallel
list_name=${DSMlist}_${hostN}

list=$(cat ${list_name})

# Run dem_align in parallel

echo "Scene alignment begins: $(date)" | tee -a $logFile
if [ "$tiltcorr" = true ] ; then
    outdir=${outdir}_tiltcorr
    
    parallel --progress "dem_align_wmask.py -tiltcorr -mask_shp_fn $mask -mode $mode -polyorder $polyorder -tol $tol -max_offset $max_offset -max_dz $max_dz -res $res -slope_lim $slope_lim -max_iter $max_iter -outdir $out_dir $ref_fn {}" ::: $list

else
    parallel --progress "dem_align_wmask.py -mask_shp_fn $mask -mode $mode -polyorder $polyorder -tol $tol -max_offset $max_offset -max_dz $max_dz -res $res -slope_lim $slope_lim -max_iter $max_iter -outdir $out_dir $ref_fn {}" ::: $list
fi

echo "Scene alignment complete: $(date)" | tee -a $logFile
echo "All output files in directory $outdir" | tee -a $logFile

cd $out_dir

    # Removing all auxiliary files
    if [ "$RM_DIR" = true ] ; then
        echo "Removing auxiliary files" | tee -a $logFile
        rm -fv *.png
        rm -fv *_filt.tif
        rm -fv *_diff.tif
    fi


t_end=$(date +%s)
t_diff=$(expr "$t_end" - "$t_start")
t_diff_hr=$(printf "%0.4f" $(echo "$t_diff/3600" | bc -l ))

echo "Total processing time for co-registration in hrs: ${t_diff_hr}"
echo "PROCESSING COMPLETE: $(date)" | tee -a $logFile

exit 0
