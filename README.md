OpenStreetMap docker script For Tile Server + Nominatim

This bash script will do the follwing:
* Download the OpenStreetMap raw data (.osm.pbf) file (world or area)
  * set WORLD=1 for using the worldwide data or WORLD=0 for using local data
* Support two OSM Services:
  * Tile Server - https://github.com/Overv/openstreetmap-tile-server/    
  * Nominatim - https://github.com/mediagis/nominatim-docker/tree/master/3.5
* For each of the two OSM Services
  * pull/create the image
  * import the osm.pbf data file (this might take minutes/hours for local data and days/weeks for world data)
  * Run the service
  * Backup the docker image into a tar.gz (if MAKE_BACKUP=1)
  * Backup the imported data into a tar.gz (if MAKE_BACKUP=1)
