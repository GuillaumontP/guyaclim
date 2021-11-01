##=====================================================
##
## Climate data for French Guyanaa
##
## Ghislain Vieilledent <ghislain.vieilledent@cirad.fr>
## Jeanne Clément <jeanne.clement@cirad.fr>
##
## Octobre 2021
##
##=====================================================

## gdal library is needed to run this script
## http://www.gdal.org/

## gdalwrap options
# from output/extent.txt
Extent <- "100000 230000 435000 642000"
Res <- "1000"
nodat <- "-9999"
proj.s <- "EPSG:4326"
proj.t <- "EPSG:32622"

# Libraries
library(glue)
library(here)
library(sf)
library(stars)
#library(raster)
library(rgdal)
library(insol) # for function daylength
library(rgrass7)

## Create some directories
dir.create(here("data_raw","worldclim_v2_1","temp")) ## Temporary folder


# Download "zip" files containing 12 GeoTiff (.tif) files, one for each month of the year (January is 1; December is 12).
# They are the average for the years 1970-2000 at 30 seconds (~1 km2) From WorldClim version 2.1.
## Monthly minimum temperature (°C).
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_tmin.zip',
              destfile=here("data_raw","worldclim_v2_1","wc2.1_30s_tmin.zip"), method = 'auto')
## Monthly maximum temperature (°C).
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_tmax.zip',
              destfile=here("data_raw","worldclim_v2_1","wc2.1_30s_tmax.zip"), method = 'auto')
## Average temperature (°C).
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_tavg.zip',
              destfile=here("data_raw","worldclim_v2_1","wc2.1_30s_tavg.zip"), method = 'auto')
## Precipitation (mm).
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_prec.zip',
              destfile=here("data_raw","worldclim_v2_1","wc2.1_30s_prec.zip"), method = 'auto')
## Wind speed (m s^-1)
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_wind.zip',
              destfile=here("data_raw", "worldclim_v2_1", "wc2.1_30s_wind.zip"), method = 'auto')
## Water vapor pressure (kPa)
download.file('http://biogeo.ucdavis.edu/data/worldclim/v2.1/base/wc2.1_30s_vapr.zip',
              destfile=here("data_raw", "worldclim_v2_1", "wc2.1_30s_vapr.zip"), method = 'auto')

# Compute standard (19) WorldClim Bioclimatic variables from monthly Tmin, Tmax, Tavg and Prec of WorldClim version 2.1. 
# Using the function r.bioclim from the GRASS GIS software.
# BIO1 = Annual Mean Temperature
# BIO2 = Mean Diurnal Range (Mean of monthly (max temp - min temp))
# BIO3 = Isothermality (BIO2/BIO7) (×100)
# BIO4 = Temperature Seasonality (standard deviation ×100)
# BIO5 = Max Temperature of Warmest Month
# BIO6 = Min Temperature of Coldest Month
# BIO7 = Temperature Annual Range (BIO5-BIO6)
# BIO8 = Mean Temperature of Wettest Quarter
# BIO9 = Mean Temperature of Driest Quarter
# BIO10 = Mean Temperature of Warmest Quarter
# BIO11 = Mean Temperature of Coldest Quarter
# BIO12 = Annual Precipitation
# BIO13 = Precipitation of Wettest Month
# BIO14 = Precipitation of Driest Month
# BIO15 = Precipitation Seasonality (Coefficient of Variation)
# BIO16 = Precipitation of Wettest Quarter
# BIO17 = Precipitation of Driest Quarter
# BIO18 = Precipitation of Warmest Quarter 
# BIO19 = Precipitation of Coldest Quarter

## Unzip worldclim 30s monthly Tmin, Tmax, Tavg and Prec.
## Reframe on French Guyana with a little margin.
guy <- sf::st_read(here("data_raw", "fao_gaul", "FAO_GAUL_GUY.kml"))
bb_ll <- st_bbox(guy, crs=st_crs(4326))
bb_ll_large <- c(floor(bb_ll[c("xmin", "ymin")]), ceiling(bb_ll[c("xmax", "ymax")]))
files.zip <- c("wc2.1_30s_tmax.zip", "wc2.1_30s_tmin.zip", "wc2.1_30s_tavg.zip", "wc2.1_30s_prec.zip")
for (i in 1:length(files.zip)){
  dst <- paste(here("data_raw","worldclim_v2_1"), files.zip[i], sep="/")
  unzip(dst, exdir=here("data_raw", "worldclim_v2_1", "temp"), overwrite=TRUE)
  files.tif <- grep("_crop_", list.files(here("data_raw", "worldclim_v2_1", "temp"), pattern="tif", full.names = TRUE),
                    invert=TRUE, value=TRUE)
  for(j in 1:length(files.tif)){
    sourcefile <- files.tif[j]
    destfile <- gsub("wc2.1_30s_", "wc2.1_30s_crop_", files.tif[j])
    cmd <- glue("gdal_translate -projwin {bb_ll_large['xmin']}  {bb_ll_large['ymax']} {bb_ll_large['xmax']} {bb_ll_large['ymin']} \\
                -projwin_srs {proj.s} {sourcefile} {destfile}")
    system(cmd)
    file.remove(sourcefile)
  }
  files.tif <- list.files(here("data_raw", "worldclim_v2_1", "temp"), pattern="tif", full.names = TRUE)
  r <- read_stars(files.tif, proxy=TRUE, along="band")
  write_stars(obj=r, type="Int16", options = c("COMPRESS=LZW","PREDICTOR=2"),
              dsn=paste(here("data_raw","worldclim_v2_1"), gsub(".zip",".tif", gsub("wc2.1_30s_","wc2.1_30s_crop_", files.zip[i])),sep="/"))
  file.remove(files.tif)
}

tmin=stack(here("data_raw","worldclim_v2_1","wc2.1_30s_crop_tmin.tif"))
tmax=stack(here("data_raw","worldclim_v2_1","wc2.1_30s_crop_tmax.tif"))
tavg=stack(here("data_raw","worldclim_v2_1","wc2.1_30s_crop_tavg.tif"))
prec=stack(here("data_raw","worldclim_v2_1","wc2.1_30s_crop_prec.tif"))
bioclim <- dismo::biovars(tmin, tmax, prec)
writeRaster(bioclim, type="Int16", options = c("COMPRESS=LZW","PREDICTOR=2"),
            filename=here("data_raw","worldclim_v2_1","wc2.1_30s_crop_bio.tif"))
## Initialize GRASS
setwd(here("data_raw"))
Sys.setenv(LD_LIBRARY_PATH=paste("/usr/lib/grass78/lib", Sys.getenv("LD_LIBRARY_PATH"),sep=":"))
# use a georeferenced raster
system(glue('grass -c {proj.s} grassdata/climate'))
# connect to grass database
initGRASS(gisBase="/usr/lib/grass78", 
          gisDbase="grassdata", home=tempdir(), 
          location="climate", mapset="PERMANENT",
          override=TRUE)
## Import raster in grass
files.tif <- list.files(here("data_raw", "worldclim_v2_1", "temp"), pattern="tif", full.names=TRUE)
for(i in 1:length(files.tif)){
system(glue("r.in.gdal --o input={files.tif[i]} \\
            output={gsub('here('data_raw', 'worldclim_v2_1', 'temp'), wc2.1_30s_crop_', '', files.tif[i])}"))
}
## Compute standard (19) WorldClim Bioclimatic using the function r.bioclim
system("r.bioclim tmin=`g.list type=rast pat=tmin_* map=. sep=,` tmax=`g.list type=rast pat=tmax_* map=. sep=,` prec=`g.list type=rast pat=prec_* map=. sep=,` out=wc2.1_30s_ workers=4 quartals=12")
# r.bioclim not found 

## function to compute PET, CWD and NDM
## PET: potential evapotranspiration (Thornthwaite equation,1948) (or (Priestley-Taylor equation,1972)?)
## CWD: climatic water deficit
## NDM: number of dry months
#== Thornthwaite functions
thorn.indices <- function(clim){
  I <- rep(0,ncell(clim))
  for (i in 1:12) {
    Tmin <- clim[[1]][,,i]
    Tmax <- clim[[1]][,,i+12]
    Tavg <- clim[[1]][,,i+24]
    I <- I+(Tavg/5)^(1.514)
  }
  alpha <- (6.75e-7)*I^3-(7.71e-5)*I^2+(1.792e-2)*I+0.49239
  return(list(I=I,alpha=alpha))
}
thorn.f <- function(Tm,I,alpha,Jday,lat,long) {
  L <- insol::daylength(lat,long,Jday,tmz=3)[,3]
  PET <- 1.6*(L/12)*(10*Tm/I)^alpha
  return(PET)
}

pet.cwd.ndm.f <- function(clim) {
  # get latitude in radians
  # xy.utm <- SpatialPoints(coordinates(clim), proj4string=CRS(paste0("+init=epsg:", 
  #                                                                   gsub("EPSG:","", proj.t))))
  # xy <- spTransform(xy.utm,CRS(paste0("+init=epsg:", gsub("EPSG:","", proj.s))))
  long_deg <- st_coordinates(clim)[,1]
  lat_deg <- st_coordinates(clim)[,2]
  # initialize
  cwd <- rep(0,ncell(clim)) 
  ndm <- rep(0,ncell(clim))
  pet <- rep(0,ncell(clim))
  # thorn.index
  ind <- thorn.indices(clim)
  # loop on months
  for (i in 1:12) {
    cat(paste("Month: ",i,"\n",sep=""))
    evap.thorn <- clim[,,,1] # Evap Thornthwaite
    Tmin <- c(clim[[1]][,,i])
    Tmax <- clim[[1]][,,i+12]
    Tavg <- clim[[1]][,,i+24]
    Prec <- clim[[1]][,,i+36]
    d <- data.frame(day=(30*i)-15,Tmin,Tmax,Tavg,lat_deg,long_deg)
    d[is.na(d)] <- 0
    ## Thornthwaite
    pet.thorn <- thorn.f(Tm=d$Tavg,lat=d$lat_deg,long=d$long_deg,
                         I=ind$I,alpha=ind$alpha,Jday=d$day)*10
    pet.thorn[is.na(Tmin)] <- NA # to correct for NA values
    values(evap.thorn) <- pet.thorn
    if (i==1) {
      PET12.thorn <- c(evap.thorn)
    }
    if (i>1) {
      PET12.thorn <- c(PET12.thorn, evap.thorn)
    }
    pet <- pet+pet.thorn # annual PET
    pe.diff <- Prec-pet.thorn
    cwd <- cwd+pmin(pe.diff,0.0) # climatic water deficit
    dm <- rep(0,ncell(clim)) # dry month
    dm[pe.diff<0] <- 1
    ndm <- ndm+dm
  }
  # make rasters
  PET <- CWD <- NDM <- clim[,,,1]
  values(PET) <- pet
  values(CWD) <- -cwd
  values(NDM) <- ndm
  NDM[is.na(PET)] <- NA # to account for NA values
  return (list(PET12=PET12.thorn,PET=PET,CWD=CWD,NDM=NDM))
}
# pet.cwd.ndm
# clim <- stack(tmin,tmax,tavg,prec)
files.tif <- paste0(here("data_raw","worldclim_v2_1","wc2.1_30s_crop_"),c("tmin","tmax","tavg","prec"),".tif")
clim <- read_stars(files.tif, along="band")
pet.cwd.ndm <- pet.cwd.ndm.f(clim)
## output stack
os <- stack(clim,bioclim,pet.cwd.ndm$PET12,pet.cwd.ndm$PET,pet.cwd.ndm$CWD,pet.cwd.ndm$NDM)
writeRaster(os,filename=here("output","current.tif"),overwrite=TRUE,
            datatype="INT2S",format="GTiff",options=c("COMPRESS=LZW","PREDICTOR=2"))

## Unzip worldclim 30s data-sets
## Reproject from lat long to UTM32N (epsg: 32622), set resolution to 1km and reframe on French Guyana
files.zip <- list.files(here("data_raw","worldclim_v2_1"), pattern="zip")
for (i in 1:length(files.zip)){
  dst <- paste(here("data_raw","worldclim_v2_1"), files.zip[i], sep="/")
  unzip(dst, exdir=here("data_raw","worldclim_v2_1", "temp"), overwrite=TRUE)
  files.tif <- list.files(here("data_raw", "worldclim_v2_1", "temp"), pattern="tif")
  for(j in 1:length(files.tif)){
    sourcefile <- paste(here("data_raw", "worldclim_v2_1", "temp"), files.tif[j], sep="/")
    destfile <- paste(here("data_raw", "worldclim_v2_1", "temp",), gsub("wc2.1_30s_", "wc2.1_1km_", files.tif[j]), sep="/")
    system(glue("gdalwarp -overwrite -s_srs {proj.s} -t_srs {proj.t} -srcnodata -32768 -dstnodata -32767 \\
        -r bilinear -tr 1000 1000 -te {Extent} -ot Int16 -of GTiff \\
        {sourcefile} \\
        {destfile}"))
    file.remove(sourcefile)
  }
  files.tif <- list.files(here("data_raw", "worldclim_v2_1", "temp"), pattern="tif")
  (r <- read_stars(paste(here("data_raw","worldclim_v2_1","temp"), files.tif, sep="/"), proxy=TRUE, along="band"))
  write_stars(obj=r, type="Int16", options = c("COMPRESS=LZW","PREDICTOR=2"),
              dsn=paste(here("data_raw","worldclim_v2_1"), gsub(".zip",".tif", gsub("wc2.1_30s_","wc2.1_1km_", files.zip[i])),sep="/"))
  file.remove(paste(here("data_raw","worldclim_v2_1","temp"), files.tif, sep="/"))
}
#file.remove(files.zip)