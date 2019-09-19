# This is a modified Cassandra image with Swift installed, to test locally 
# the upload and download of data of Cassandra towards a Swift object storage

FROM cassandra:3.11.3

RUN apt-get update; \
    apt-get install -y --no-install-recommends python3 python3-swiftclient; \
    rm -rf /var/lib/apt/lists/*
