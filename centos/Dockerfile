FROM centos:7
MAINTAINER donglei, xiaosan@outlook.com

ENV KONG_VERSION 0.11.2

RUN yum install -y wget https://bintray.com/kong/kong-community-edition-rpm/download_file?file_path=dists%2Fkong-community-edition-$KONG_VERSION.el7.noarch.rpm && \
    yum clean all && \
    mkdir -p /usr/local/kong/nginx-lua-prometheus

COPY ./nginx-lua-prometheus /usr/local/kong/nginx-lua-prometheus
COPY docker-entrypoint-nginx.sh /docker-entrypoint.sh
COPY nginx.lua /usr/local/share/lua/5.1/kong/templates/
COPY nginx_kong.lua /usr/local/share/lua/5.1/kong/templates/
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444 9145

STOPSIGNAL SIGTERM
#CMD ["ls", "/usr/local/share/lua/5.1/kong/templates/"]
CMD ["/usr/local/openresty/nginx/sbin/nginx", "-c", "/usr/local/kong/nginx.conf", "-p", "/usr/local/kong/"]
