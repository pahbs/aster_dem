#!/bin/bash
#
#   DEM gridding and cloudmasking of point clouds from AMES Stereo Pipeline 
#	'cr' DEMs produced by differencing orig DEMs from an input reference
#		This changes cloud elevs to no data (-99);
#	    This script is the last before co-reg
#
# Get a refdem from TDX90m
# >userfs02/refdem$ gdalbuildvrt $PWD/TDM1_DEM__30_fairbanks_DEM.tif ../data/tandemx/TDM90/TDM1_DEM__30_N6[3456]W1[45]*/DEM/*DEM.tif
#
# Make the list of DEMs like this:
# pmontesa@himat102:/att/pubrepo/hma_data/ASTER$ find L1A/*/outASP/ -type f -name out-DEM.tif > list_DEM
# which produces lines like this:
# line=L1A/AST_20110604_00306042011060347/outASP/out-DEM.tif
# the scenName is returned below
# sceneName=$(echo $1 | cut -d'/' -f 2)

sceneName=$1
L1Adir=$2

echo; echo "Scene name at read-in: $sceneName"; echo

# Get topDir from L1Adir
topDir=$(dirname $L1Adir)
echo "Top dir: $topDir"

gdal_calc_opt="--co=\"TILED=YES\" --co=\"COMPRESS=LZW\" --co=\"BIGTIFF=YES\""
gdal_opt='-co TILED=YES -co COMPRESS=LZW -co BIGTIFF=YES'

#Some gentle erosion at this stage
erode_len=$3

# Outpu DEM pixel res, in meters
res=$4

# Ref DEM for elev threshold
refDEM=$5
#refDEM=/att/nobackup/pmontesa/userfs02/data/srtm_index.vrt
#refDEM=/att/pubrepo/hma_data/products/nasadem/hma_nasadem_hgt_merge_hgt_aea.tif
# Ref DEM for co-reg
#refDEMcoreg=/att/pubrepo/hma_data/products/hrsi_dsm/mos/hma_20170716_mos/mos_8m/hma_20170716_mos_8m.vrt

# Specify 'hardlink' to duplicate data, writing nicely named files to common top level dirs
LINK=${6:-'symlink'}

#Elev diff threshold from ref DEM
elev_diff_thresh=${7:-'100'}

test_str=""

now="$(date +'%Y%m%d%T')"

# Process the AST_L1A dir indicated with the sceneName
out_dir=$L1Adir/$sceneName/outASP
cd $topDir

hostN=`/bin/hostname -s`

mkdir -p ${L1Adir}_out

mkdir -p ${L1Adir}_out/orig
mkdir -p ${L1Adir}_out/orig/dsm

mkdir -p ${L1Adir}_out/cr${test_str}
mkdir -p ${L1Adir}_out/cr${test_str}/dsm
mkdir -p ${L1Adir}_out/cr${test_str}/hs


cd $L1Adir
logFile=${topDir}/logs${test_str}/point2dem_$hostN_$sceneName.log

echo "Running ASP point2dem..."
echo "START: $(date)" | tee -a $logFile

echo "Creating orig DEM with point2dem..." | tee -a $logFile
echo "Eroding $erode_len pixels" | tee -a $logFile

in_pc=$out_dir/out-PC.tif
dem=$out_dir/out-DEM.tif

# Get UTM projection from input projected nadir Band3
prj_utm="$(utm_proj_select.py $L1Adir/$sceneName/in-Band3N_proj.tif)"
echo "Projection for DEM: $prj_utm" | tee -a $logFile

base_dem_opts="--nodata-value -99 --threads=4 -r earth --t_srs \"${prj_utm}\""
dem_opts=''
dem_opts+=" --tr $res --erode-length $erode_len"
dem_opts+=" --remove-outliers --remove-outliers-params 75.0 3.0"

cmd="point2dem $base_dem_opts $dem_opts $in_pc -o $out_dir/out"
echo $cmd | tee -a $logFile
eval $cmd

dem_list="${refDEM} $dem"

echo "Creating 'cr' DEM (cloud-removed)..." | tee -a $logFile

echo "Elevation Difference Threshold (m): $elev_diff_thresh" | tee -a $logFile
echo "	Removing pixels from input DEM > $elev_diff_thresh difference from:" | tee -a $logFile
echo "	$refDEM" | tee -a $logFile
echo "" | tee -a $logFile

echo "[1] Create warped refDEM" | tee -a $logFile
cmd="warptool.py -t_srs \"$dem\" -tr \"$dem\" -te intersection $dem_list -outdir $out_dir"
echo $cmd ; eval $cmd

dem_warp_ref=$(echo $out_dir/$(basename $refDEM) | sed 's/.vrt/\.DEM/g; s/.tif/\.DEM/g; s/\.DEM/_warp.tif/g')
##dem_warp_source=$(echo $out_dir/$(basename ${dem%.*})_warp.tif )
echo "Out warp ref DEM for elev threshold: $dem_warp_ref" | tee -a $logFile

echo " " | tee -a $logFile
echo "[2] Differencing the orig DEM from the warped refDEM, removing clouds, producing cr DEM" | tee -a $logFile
cmd="gdal_calc.py ${gdal_calc_opt} --overwrite -A $dem -B $dem_warp_ref --outfile=${dem%.tif}_cr${test_str}.tif --calc=\"-99*((A-B)>${elev_diff_thresh})+A*(A-B<=${elev_diff_thresh})\" --NoDataValue=-99"
echo $cmd | tee -a $logFile
eval $cmd

rm $dem_warp_ref

# Hillshades
gdaldem hillshade ${gdal_opt} -alt 45 ${dem%.tif}_cr${test_str}.tif ${dem%.tif}_cr-hs-e45.tif
gdaldem hillshade ${gdal_opt} -alt 45 ${dem%.tif}${test_str}.tif ${dem%.tif}-hs-e45.tif
#hillshade ${dem%.tif}_cr${test_str}.tif -o ${dem%.tif}_cr-hs-e45.tif -e 45 --nodata-value 0

# Symlinks or hardlinks to nicely named DEMs stored in a common top level dir
if [ "$LINK" != "hardlink" ] ; then
    echo ; echo "Creating symlink of output DEM:"
    ln -sf $dem ${L1Adir}_out/orig/dsm/${sceneName}_DEM.tif
    ln -sf ${dem%.tif}_cr-hs-e45.tif ${L1Adir}_out/cr${test_str}/hs/${sceneName}_cr-hs-e45.tif
    ln -sf ${dem%.tif}_cr${test_str}.tif ${L1Adir}_out/cr${test_str}/dsm/${sceneName}_DEM_cr.tif
else
    echo ; echo "Creating hardlink duplicate of output DEM:" 
    rsync -as $dem ${L1Adir}_out/orig/dsm/${sceneName}_DEM.tif
    rsync -as ${dem%.tif}_cr-hs-e45.tif ${L1Adir}_out/cr${test_str}/hs/${sceneName}_cr-hs-e45.tif
    rsync -as ${dem%.tif}_cr${test_str}.tif ${L1Adir}_out/cr${test_str}/dsm/${sceneName}_DEM_cr.tif
fi
echo "from :: L1A/<sceneName>/outASP"
echo "to   :: L1A_out/orig/dsm & cr/dsm" ; echo

echo "----------<END> $(date)" | tee -a $logFile

