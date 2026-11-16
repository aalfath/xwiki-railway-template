# XWiki on Railway: the official image, pinned by version and digest.
# Upstream: https://hub.docker.com/_/xwiki (tag 18.9.0-postgres-tomcat: Tomcat 10, Java 21, PostgreSQL JDBC)
FROM xwiki:18.9.0-postgres-tomcat@sha256:3e3d28bfb102bd7005f8a31ad0accb55e27d8edd42d0b1ba8a8e52b43f9afb78

# busybox httpd serves a "being set up" page on $PORT during the first boot only.
RUN apt-get update \
 && apt-get install -y --no-install-recommends busybox \
 && rm -rf /var/lib/apt/lists/* \
 && busybox --list | grep -qx httpd \
 && cp /usr/local/tomcat/conf/server.xml /usr/local/tomcat/conf/server.xml.orig

COPY railway-start.sh /usr/local/bin/railway-start.sh
RUN chmod 755 /usr/local/bin/railway-start.sh

# All wiki data (attachments, installed extensions, Solr index, logs) lives here: mount a volume.
VOLUME /usr/local/xwiki

ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
