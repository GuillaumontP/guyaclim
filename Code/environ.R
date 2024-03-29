##
## Environmental data for French Guyana
##
## Ghislain Vieilledent <ghislain.vieilledent@cirad.fr>
## Jeanne Clément <jeanne.clement@cirad.fr>
##
## Octobre 2021
##


## gdal library is needed to run this script
## http://www.gdal.org/

## GRASS GIS 7.x.x is also needed to run this script
## https://grass.osgeo.org/

## Read argument for download
## Set "down" to TRUE if you want to download the sources. Otherwise, the data already provided in the data_raw folder will be used.
arg <- commandArgs(trailingOnly=TRUE)
down <- TRUE
if (length(arg)>0) {
  down <- arg[1]
}

# Libraries
library(glue)
library(here)
library(sf)
library(stars)
library(rgdal)
library(rgrass7)

## gdalwrap options
Extent <- readLines(here("output/extent_short.txt"))
Res <- "1000"
nodat <- "-9999"
proj.s <- "EPSG:4326"
proj.t <- "EPSG:2972"
# "EPSG:32622" not legal projection

dir.create(here("data_raw", "srtm_v1_4_90m")) ## folder for environmental data
dir.create(here("data_raw", "srtm_v1_4_90m", "temp")) ## folder for temporary data

#====== Elevation, slope aspect, roughness #======
# SRTM at 90m resolution from https://dwtkns.com/srtm/ version 4.1
## Download and unzip CGIAR-CSI 90m DEM data

# tiles_srtm
tiles_srtm <- function(extent_latlong){
# Compute lat/long tiles for SRTM data from an extent.
# This function computes lat/long tiles for SRTM data from an extent
# in lat/long. See `<http://dwtkns.com/srtm/>`_. SRTM tiles are 5x5
# degrees. x: -180/+180, y: +60/-60.
# :param extent_latlong: Extent in lat/long: (xmin, ymin, xmax, ymax).
# :return: A tuple of two strings indicating tile numbers for lat and long.

# Tiles for SRTM data
xmin_latlong = floor(extent_latlong[1])
ymin_latlong = floor(extent_latlong[2])
xmax_latlong = ceiling(extent_latlong[3])
ymax_latlong = ceiling(extent_latlong[4])
# Compute SRTM tile numbers
tile_left = as.integer(ceiling((xmin_latlong + 180.0) / 5.0))
tile_right = as.integer(ceiling((xmax_latlong + 180.0) / 5.0))
if (tile_right == tile_left){
  # Trick to make curl globbing work in data_country.sh
  tile_right = tile_left + 1
}
tile_top = as.integer(ceiling((-ymax_latlong + 60.0) / 5.0))
tile_bottom = as.integer(ceiling((-ymin_latlong + 60.0) / 5.0))
if (tile_bottom == tile_top){
  tile_bottom = tile_top + 1
}
# Format variables, zfill is for having 01 and not 1
tiles_long = c(tile_left, tile_right)
tiles_lat = c(tile_top, tile_bottom)
return(list(long = tiles_long, lat=tiles_lat))
}
ISO_country_code <- "GUF"
borders <- sf::st_read(here("data_raw", "fao_gaul", paste0("gadm36_", ISO_country_code, ".gpkg")),
                       layer=paste0("gadm36_", ISO_country_code, "_0"))
extent_latlong <- st_bbox(borders, crs=4326)
tiles <- tiles_srtm(extent_latlong)
tiles <- paste(stringr::str_pad(rep(tiles$long[1]:tiles$long[2],
                                    each=length(tiles$lat[1]:tiles$lat[2])),
                                width=2, pad="0"), 
               stringr::str_pad(tiles$lat[1]:tiles$lat[2], width=2, pad="0"), sep="_")
#tiles <- c("26_11","26_12")
for (i in 1:length(tiles)) {
  dst <- paste0(here("data_raw", "srtm_v1_4_90m", "temp", "srtm_"), tiles[i],".zip")
  if (down) {
    url.tile <- paste0("https://srtm.csi.cgiar.org/wp-content/uploads/files/srtm_5x5/TIFF/srtm_",tiles[i],".zip")
    download.file(url=url.tile,destfile=dst,method="wget",quiet=TRUE)
  }
  unzip(dst, exdir=here("data_raw", "srtm_v1_4_90m", "temp"), overwrite=TRUE)
}
## Mosaic with gdalbuildvrt
destfile <- here("data_raw", "srtm_v1_4_90m", "temp", "elevation.vrt")
sourcefile <- here("data_raw", "srtm_v1_4_90m", "temp", paste0("srtm_", tiles, ".tif"))
writeLines(sourcefile, here("data_raw", "srtm_v1_4_90m", "temp","files.txt"))
sourcefile <-  here("data_raw", "srtm_v1_4_90m", "temp","files.txt")
system(glue("gdalbuildvrt {destfile} -input_file_list {sourcefile}"))

## Reproject from lat long to UTM32N (epsg: 32622) and reframe on French Guyana
# (dstnodata need to be set to 32767 as we pass from Int16 (nodata=-32768) to INT2S (nodata=-32767) in R)
sourcefile <- here("data_raw", "srtm_v1_4_90m", "temp", "elevation.vrt")
destfile <- here("data_raw", "srtm_v1_4_90m", "temp", "elevation.tif")
system(glue("gdalwarp -overwrite -s_srs {proj.s} -t_srs {proj.t} -srcnodata -32768 -dstnodata -32767 \\
        -r bilinear -tr 90 90 -te {Extent} -of GTiff \\
        {sourcefile} \\
        {destfile}"))
# elev <- read_stars(here("data_raw", "srtm_v1_4_90m", "temp", "elevation.tif"))
# border <- sf::st_read(here("data_raw", "fao_gaul", paste0("gadm36_", ISO_country_code, ".gpkg")),
#                       layer=paste0("gadm36_", ISO_country_code, "_0"))
# border <- st_transform(border, crs=st_crs(elev))
# plot(elev, axes=TRUE,reset = FALSE)
# plot(border$geom, add=TRUE, reset=FALSE)

## Compute slope, aspect and roughness using gdaldem 
# compute slope
in_f <- here("data_raw", "srtm_v1_4_90m", "temp", "elevation.tif")
out_f <- here("data_raw", "srtm_v1_4_90m", "temp", "slope.tif")
cmd <- glue('gdaldem slope {in_f} {out_f} -co "COMPRESS=LZW" -co "PREDICTOR=2"')
system(cmd)
# compute aspect
out_f <- here("data_raw", "srtm_v1_4_90m", "temp", "aspect.tif")
cmd <- glue('gdaldem aspect {in_f} {out_f} -co "COMPRESS=LZW" -co "PREDICTOR=2"')
system(cmd)
# compute roughness
out_f <- here("data_raw", "srtm_v1_4_90m", "temp", "roughness.tif")
cmd <- glue('gdaldem roughness {in_f} {out_f} -co "COMPRESS=LZW" -co "PREDICTOR=2"')
system(cmd)
# Resolution from 90m x 90m to 1000m x 1000m using gdalwarp
# elevation
out_f <- here("data_raw", "srtm_v1_4_90m", "elevation_1km.tif")
cmd <- glue('gdalwarp -srcnodata -32767 -dstnodata -32767 -r bilinear -tr 1000 1000 -te {Extent} \\
        -co "COMPRESS=LZW" -co "PREDICTOR=2" -overwrite {in_f} {out_f}')
system(cmd)
# aspect
in_f <- here("data_raw", "srtm_v1_4_90m", "temp", "aspect.tif")
out_f <-here("data_raw", "srtm_v1_4_90m", "aspect_1km.tif")
cmd <- glue('gdalwarp -srcnodata {nodat} -dstnodata -32767 -r bilinear -tr 1000 1000 -te {Extent} \\
        -co "COMPRESS=LZW" -co "PREDICTOR=2" -overwrite {in_f} {out_f}')
system(cmd)
# slope
in_f <- here("data_raw", "srtm_v1_4_90m", "temp", "slope.tif")
out_f <- here("data_raw", "srtm_v1_4_90m", "slope_1km.tif")
cmd <- glue('gdalwarp -srcnodata {nodat} -dstnodata -32767 -r bilinear -tr 1000 1000 -te {Extent} \\
        -co "COMPRESS=LZW" -co "PREDICTOR=2" -overwrite {in_f} {out_f}')
system(cmd)
# roughness
in_f <- here("data_raw", "srtm_v1_4_90m", "temp", "roughness.tif")
out_f <- here("data_raw", "srtm_v1_4_90m", "roughness_1km.tif")
cmd <- glue('gdalwarp -srcnodata {nodat} -dstnodata -32767 \\
        -r bilinear -tr 1000 1000 -te {Extent} -ot Int16 -of GTiff \\
        -co "COMPRESS=LZW" -co "PREDICTOR=2" -overwrite {in_f} {out_f}')
system(cmd)

#=== Solar radiation =====
# with r.sun at 90m resolution 
# Solar radiation (in Wh.m-2.day-1) was computed from altitude,
# slope and aspect using the function r.sun from the GRASS GIS software.
# We incorporated the shadowing effect of terrain to compute the solar radiation.
# Solar radiation was computed for the Julian day 79 (20th of March for regular years=equinox).
## Initialize GRASS
setwd(here("data_raw"))
Sys.setenv(LD_LIBRARY_PATH=paste("/usr/lib/grass78/lib", Sys.getenv("LD_LIBRARY_PATH"), sep=":"))
# use a georeferenced raster
elevation <- here("data_raw", "srtm_v1_4_90m", "temp", "elevation.tif")
system(glue('grass -c {elevation} grassdata/environ'))
# connect to grass database
initGRASS(gisBase="/usr/lib/grass78", 
          gisDbase="grassdata", home=tempdir(), 
          location="environ", mapset="PERMANENT",
          override=TRUE)
## Import raster in grass
# -e to get the whole map for NCL 
system(glue("r.in.gdal --o input={elevation} output=elevation"))
slope <- here("data_raw", "srtm_v1_4_90m", "temp", "slope.tif")
system(glue("r.in.gdal --o input={slope} output=slope"))
aspect <- here("data_raw", "srtm_v1_4_90m", "temp", "aspect.tif")
system(glue("r.in.gdal --o input={aspect} output=aspect"))
# Compute radiation
cmd <- glue("r.sun --o --verbose elevation=elevation aspect=aspect slope=slope day=79 glob_rad=global_rad")
system(cmd)
# Export
system(glue("r.out.gdal -f --overwrite input=global_rad \\
  			 output={here('data_raw', 'srtm_v1_4_90m', 'temp', 'srad.tif')} type=Int16 nodata=-32767 \\
  			 createopt='compress=lzw,predictor=2'"))
# Resolution from 90m x 90m to 1000m x 1000m using gdalwarp
# srad
in_f <- here("data_raw", "srtm_v1_4_90m", "temp", "srad.tif")
out_f <- here("data_raw", "srtm_v1_4_90m", "srad_1km.tif")
cmd <- glue('gdalwarp -srcnodata -32767 -dstnodata -32767 -s_srs {proj.t} -t_srs {proj.t} \\
        -r bilinear -tr 1000 1000 -te {Extent} -ot Int16 -of GTiff \\
        -co "COMPRESS=LZW" -co "PREDICTOR=2" -overwrite {in_f} {out_f}')
system(cmd)

## =========== Forest: percentage of forest in 1km2 ========

## References:
## (1) Forestatrisk project: https://forestatrisk.cirad.fr/rawdata.html

## Create directory
dir.create(here("data_raw","tmf_ec_jrc"))

# Download forest cover of Guyana in 2000 from tmf_ec_jrc (see note)
if (down) {
  download.file("https://drive.google.com/uc?export=download&id=19NKsPHgpbQoNut2apA3L1AOB8tBnUu8S",
                destfile=here("data_raw", "tmf_ec_jrc", "forest_t3.tif"), method = 'auto', mode="wb")
}
# forest <- read_stars(here("data_raw", "tmf_ec_jrc", "forest_t3.tif"), along="band")
# plot(forest)
## Reproject from South America Albers Equal Area Conic (ESRI:102033) to UTM32N (EPSG:2972) 
# Resampling from 30x30m to 1000x1000m using sum method 
## Reframe on French Guyana and set no data values 
sourcefile <- here("data_raw", "tmf_ec_jrc", "forest_t3.tif")
destfile <- here("data_raw", "tmf_ec_jrc", "forest_n.tif")
# mode: mode resampling, selects the value which appears most often of all the sampled points.
# In the case of ties, the first value identified as the mode will be selected.
system(glue("gdalwarp -overwrite \\
        -te {Extent} -tr 1000 1000 -r mode \\
        -s_srs ESRI:102033 -t_srs {proj.t} -co 'GEOTIFF_KEYS_FLAVOR=ESRI_PE' \\
        -ot Int16 -of GTiff \\
        {sourcefile} \\
        {destfile}"))
# Set extent and NA's 
# -s_srs ESRI:102033 -t_srs {proj.t} 
forest_n <- read_stars(here("data_raw", "tmf_ec_jrc", "forest_n.tif"), along="band")
ISO_country_code <- "GUF"
border <- sf::st_read(here("data_raw", "fao_gaul", paste0("gadm36_", ISO_country_code, ".gpkg")),
                      layer=paste0("gadm36_", ISO_country_code, "_0"))
border <- st_transform(border, crs=st_crs(forest_n))
forest_n <- st_crop(forest_n, border)
write_stars(obj=forest_n, options = c("COMPRESS=LZW","PREDICTOR=2"),
            type="Int16", overwrite=TRUE, 
            dsn=here("data_raw", "tmf_ec_jrc", "forest_1km_crop.tif"))
plot(forest_n, axes=TRUE, reset=FALSE)
plot(border$geom, add=TRUE, reset=FALSE)
## Correction Mada if forest_n > 555 (more than 50% of the 1km cell is covered by land)
## Indeed, 555*30*30 = 499500 m2 and 556*30*30 = 500400 m2
# sourcefile <- here("data_raw", "tmf_ec_jrc", "forest_n.tif")
# destfile <- here("data_raw", "tmf_ec_jrc", "forest_1km.tif")
# system(glue("gdal_calc.py --overwrite -A {sourcefile} --calc='(A>555)' --outfile={destfile}"))
# r <- read_stars(destfile)
# plot(r, reset=FALSE, axes=TRUE)
# border <- sf::st_read(here("data_raw", "fao_gaul", paste0("gadm36_", ISO_country_code, ".gpkg")),
#                      layer=paste0("gadm36_", ISO_country_code, "_0"))# border <- st_transform(border,crs=st_crs(r))
# plot(border$geom, add=TRUE, reset=FALSE)
# Distance to coast
# gdal.proximity
# Distance to river 
# Distance to road
# Perturbation probability (forestatrisk)