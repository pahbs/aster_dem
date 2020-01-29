# aster_dem
These shell scripts are part of a workflow to derive ASTER L1A DEMs. 

They are used to download ASTER L1A data from EarthData.nasa.gov (using Order IDs), unzip, preprocess, and run stereogrammetry routines on the L1A scenes.

This workflow uses a reference DEM (with full study area coverage) to mapproject input and remove cloud-related elevations errors in output.

These shell scripts are wrappers for the stereogrammetry and gridding routines available in the Ames Stereo Pipeline software.
https://ti.arc.nasa.gov/tech/asr/groups/intelligent-robotics/ngt/stereo/

Workflow:
[1] Select and order ASTER L1A scenes from earthdata.nasa.gov
[2] Wait for email(s)
[3] Get every "order ID" from every email and put each on a line in a list
[4] do_aster_wget.sh $NOBACKUP/userfs02/data/ASTER_<name>_order_list <name>
[5] do_aster_preprocess.sh $NOBACKUP/userfs02/data/ASTER/L1A_orders/<name>/scenes.zip.list batch_<name> $NOBACKUP/userfs02/data true"
[6] do_aster_stereo.sh list_do_aster_stereo_batch_<name> 30 $NOBACKUP/userfs02/data $NOBACKUP/userfs02/refdem/<DEMname>.tif hardlink true true true true 3 3 49 0
