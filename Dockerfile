FROM cassandra:3.11.3

RUN echo "-Xms650M" >> /etc/cassandra/jvm.options
RUN echo "-Xmx650M" >> /etc/cassandra/jvm.options

RUN apt-get update; \
    apt-get install -y --no-install-recommends python3 python3-swiftclient; \
    rm -rf /var/lib/apt/lists/*

ADD check_dependencies.sh /root
ADD dataSwift.sh /root
ADD localDataBackup.sh /root
ADD localDataRestore.sh /root
ADD swiftDataBackup.sh /root
ADD swiftDataRestore.sh /root
ADD swiftDataSchemaRestore.sh /root
ADD truncateAll.sh /root
