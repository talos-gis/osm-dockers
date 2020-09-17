#! /bin/bash

WORLD=0
MAKE_BACKUP=1
OSM_PREFIX=osm-13

VOLUME_DIR=/media/gold/$OSM_PREFIX
BACKUP_DIR=/media/gold/$OSM_PREFIX-Backup
RAW_DATA_DIR=/home/user/$OSM_PREFIX
TILER_PORT=8080
NOMINATIM_PORT=7070

##############

if [ "$WORLD" = 1 ] ; then
	echo using full planet pbf: $PBF...
	echo https://planet.openstreetmap.org/
	PBF=planet-200907.osm.pbf
	PBF_DOWNLOAD_PREFIX=https://ftp5.gwdg.de/pub/misc/openstreetmap/planet.openstreetmap.org/pbf
else 
	echo using lolcal pbf: $PBF...
	echo https://download.geofabrik.de/asia/israel-and-palestine.html
	PBF=israel-and-palestine-200913.osm.pbf
	PBF_DOWNLOAD_PREFIX=https://download.geofabrik.de/asia
fi

#############

function IMAGE_NAME_TO_FILE_NAME()
{
	local func_result=${1//\//_}
	func_result=${func_result//:/_}
	echo "$func_result"
}

function CREATE_BACKUP_IMAGE()
{
	local IMAGE_NAME=$1
	local BACKUP_DIR=$2

	local OUTPUT=$BACKUP_DIR/"$(IMAGE_NAME_TO_FILE_NAME $IMAGE_NAME)".tar.gz

	echo backup: docker save the image into $OUTPUT... 	
	docker save $IMAGE_NAME | gzip > $OUTPUT
}

function CREATE_BACKUP_DIR()
{
	local VOLUME_NAME=$1
	local BACKUP_DIR=$2
	local VOLUME_DIR=$3

	local OUTPUT=$BACKUP_DIR/"$(IMAGE_NAME_TO_FILE_NAME $VOLUME_NAME)".tar.gz

	echo zipping the volume into $OUTPUT...
	tar -czvf $BACKUP_DIR/$VOLUME_NAME.tar.gz -C $VOLUME_DIR/$VOLUME_NAME .
}

function DOWNLOAD_FILE()
{
	local FILENAME=$1
	local DOWNLOAD_PREFIX=$2
	local RAW_DATA_DIR=$3

	local FILE=$RAW_DATA_DIR/$FILENAME
	if [ ! -f "$FILE" ]; then
	echo $FILE does not exist, download it...
	wget $DOWNLOAD_PREFIX/$FILENAME -P $RAW_DATA_DIR
	fi
}


#############

mkdir -p $VOLUME_DIR
echo VOLUME_DIR=$VOLUME_DIR

mkdir -p $RAW_DATA_DIR
echo RAW_DATA_DIR=$RAW_DATA_DIR

if [ "$MAKE_BACKUP" = 1 ] ; then
	mkdir -p $BACKUP_DIR
	echo BACKUP_DIR=$BACKUP_DIR
fi

###############

DOWNLOAD_FILE $PBF $PBF_DOWNLOAD_PREFIX $RAW_DATA_DIR

###############
echo https://switch2osm.org/

TILER_DOCKER_NAME=overv/openstreetmap-tile-server
TILER_DOCKER_FULL_NAME=$TILER_DOCKER_NAME
TILER_DOCKER_FULL_FILENAME="$(IMAGE_NAME_TO_FILE_NAME $TILER_DOCKER_FULL_NAME)"

TILER_NAME=$TILER_DOCKER_FULL_FILENAME-volume-$PBF
TILER_DATA_VOLUME=$OSM_PREFIX-data-$TILER_NAME
TILER_TILES_VOLUME=$OSM_PREFIX-tiles-$TILER_NAME
TILER_NODES_VOLUME=$OSM_PREFIX-nodes-$TILER_NAME

time docker pull $TILER_DOCKER_FULL_NAME

mkdir $VOLUME_DIR/$TILER_DATA_VOLUME
docker volume create --name $TILER_DATA_VOLUME --opt type=none --opt device=$VOLUME_DIR/$TILER_DATA_VOLUME --opt o=bind

mkdir $VOLUME_DIR/$TILER_TILES_VOLUME
docker volume create --name $TILER_TILES_VOLUME --opt type=none --opt device=$VOLUME_DIR/$TILER_TILES_VOLUME --opt o=bind

mkdir $VOLUME_DIR/$TILER_NODES_VOLUME
docker volume create --name $TILER_NODES_VOLUME --opt type=none --opt device=$VOLUME_DIR/$TILER_NODES_VOLUME --opt o=bind

time docker run \
	--name $OSM_PREFIX-tiler-server-importer \
	-v $RAW_DATA_DIR/$PBF:/data.osm.pbf \
	-v $TILER_DATA_VOLUME:/var/lib/postgresql/12/main \
	-v $TILER_TILES_VOLUME:/var/lib/mod_tile \
	-v $TILER_NODES_VOLUME:/nodes \
	-e "OSM2PGSQL_EXTRA_ARGS=--flat-nodes /nodes/flat_nodes.bin" \
	$TILER_DOCKER_FULL_NAME \
	import

docker run \
	--name $OSM_PREFIX-tiler-server \
	-p $TILER_PORT:80 \
	-v $TILER_DATA_VOLUME:/var/lib/postgresql/12/main \
	-v $TILER_TILES_VOLUME:/var/lib/mod_tile \
	-e ALLOW_CORS=enabled \
	-d $TILER_DOCKER_FULL_NAME \
	run

echo OpenStreetMap Tile-Service is ready, access the top tile via: http://localhost/tile/0/0/0.png

if [ "$MAKE_BACKUP" = 1 ] ; then
	echo creating backup of the image and the volume...
	time CREATE_BACKUP_IMAGE $TILER_DOCKER_FULL_NAME $BACKUP_DIR
	time CREATE_BACKUP_DIR $TILER_DATA_VOLUME $BACKUP_DIR $VOLUME_DIR
	time CREATE_BACKUP_DIR $TILER_TILES_VOLUME $BACKUP_DIR $VOLUME_DIR
	time CREATE_BACKUP_DIR $TILER_NODES_VOLUME $BACKUP_DIR $VOLUME_DIR
	echo backup of the image and the volume is ready!
fi


###############
echo https://github.com/mediagis/nominatim-docker/tree/master/3.5
https://nominatim.org/release-docs/latest/admin/Installation/

NOMI_DOCKER_DIR=$RAW_DATA_DIR
NOMI_DOCKER_GIT=mediagis_nominatim-docker
NOMI_DOCKER_NAME=mediagis/nominatim
NOMI_DOCKER_VERSION=3.5

NOMI_DOCKER_FULL_NAME=$NOMI_DOCKER_NAME:$NOMI_DOCKER_VERSION
NOMI_DOCKER_FULL_FILENAME="$(IMAGE_NAME_TO_FILE_NAME $NOMI_DOCKER_FULL_NAME)"

NOMI_NAME=osm-$NOMI_DOCKER_FULL_FILENAME-$PBF
NOMI_BIND=$VOLUME_DIR/$NOMI_NAME

NOMI_WIKI=wikimedia-importance.sql.gz
NOMI_WIKI_DOWNLOAD_PREFIX=https://www.nominatim.org/data

DOWNLOAD_FILE $NOMI_WIKI $NOMI_WIKI_DOWNLOAD_PREFIX $RAW_DATA_DIR

mkdir -p $NOMI_BIND
rm -Rf $NOMI_BIND/postgresdata

echo building nominatime docker image: $NOMI_DOCKER_DIR/$NOMI_DOCKER_GIT/$NOMI_DOCKER_VERSION ...

git clone https://github.com/$NOMI_DOCKER_NAME-docker.git $NOMI_DOCKER_DIR/$NOMI_DOCKER_GIT
time docker build --pull --rm -t $NOMI_DOCKER_FULL_NAME $NOMI_DOCKER_DIR/$NOMI_DOCKER_GIT/$NOMI_DOCKER_VERSION

echo running nominatim import: $NOMI_DOCKER_FULL_NAME ...
time docker run \
	--name $OSM_PREFIX-nominatim-server-importer \
	-t \	
	-v $NOMI_BIND:/data \
	-v $RAW_DATA_DIR/$PBF:/data/$PBF \
	-v $RAW_DATA_DIR/$NOMI_WIKI:/app/src/data/$NOMI_WIKI \
	$NOMI_DOCKER_FULL_NAME \
	sh /app/init.sh /data/$PBF postgresdata 4

docker run \
	--name $OSM_PREFIX-nominatim-server \
	--restart=always \
	-p 6432:5432 \
	-p $NOMINATIM_PORT:8080 \
	-v $NOMI_BIND/postgresdata:/var/lib/postgresql/12/main \
	-d $NOMI_DOCKER_FULL_NAME bash /app/start.sh

echo OSM Nominatim Server is Ready, access it via: http://localhost:7070/

if [ "$MAKE_BACKUP" = 1 ] ; then
	echo creating backup of the image and the volume...
	time CREATE_BACKUP_IMAGE $NOMI_DOCKER_FULL_NAME $BACKUP_DIR
	time CREATE_BACKUP_DIR $NOMI_NAME $BACKUP_DIR $VOLUME_DIR
	echo backup of the image and the volume is ready!
fi

#######################

echo Done!

