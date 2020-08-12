FROM nginx:alpine

MAINTAINER Vladimir Che <vl.che@ncube.cloud>

# nginx:alpine contains NGINX_VERSION environment variable, like so:
# ENV NGINX_VERSION 1.19.1

# MODSECURITY version
ENV VERSION=${NGINX_VERSION} \
    MODSECURITY_VERSION=3 \
    OWASPCRS_VERSION=3.3.0 \
    WORKING_DIR="/src"

# Build-time metadata as defined at http://label-schema.org
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
ARG MODSECURITY_VERSION
ARG OWASPCRS_VERSION
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="NGINX with ModSecurity, Certbot and lua support" \
      org.label-schema.description="Provides nginx ${NGINX_VERSION} with ModSecurity v${MODSECURITY_VERSION} (OWASP ModSecurity Core Rule Set CRS ${OWASPCRS_VERSION}) and lua support for certbot --nginx. Using Python for Let's Encrypt Certbot" \
      org.label-schema.url="https://ncube.cloud/about/opensource" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/vlche/docker-nginx-waf" \
      org.label-schema.vendor="Vladimir Che" \
      org.label-schema.version=v$VERSION \
      org.label-schema.schema-version="1.0"

# For latest build deps, see https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN apk add --no-cache --virtual .build-deps \
  gcc \
  libc-dev \
  make \
  openssl-dev \
  pcre-dev \
  zlib-dev \
  linux-headers \
  perl-dev \
  libedit-dev \
  mercurial \
  bash \
  alpine-sdk \
  findutils \
  curl \
  gnupg \
  libxslt-dev \
  gd-dev \
  geoip-dev \
# modsecurity dependencies
  libtool autoconf automake yajl-dev curl-dev libmaxminddb-dev && \
  echo "Downloading sources..." && \
  mkdir /src && cd /src && \
  git clone --depth 1 -b v${MODSECURITY_VERSION}/master --single-branch https://github.com/SpiderLabs/ModSecurity && \
  git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && \
  wget -qO modsecurity.conf https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v${MODSECURITY_VERSION}/master/modsecurity.conf-recommended && \
  wget -qO unicode.mapping  https://raw.githubusercontent.com/SpiderLabs/ModSecurity/49495f1925a14f74f93cb0ef01172e5abc3e4c55/unicode.mapping && \
  wget -qO - https://github.com/coreruleset/coreruleset/archive/v${OWASPCRS_VERSION}.tar.gz | tar xzf  - -C /src && \
  wget -qO - https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xzf  - -C /src && \
  echo "build modsecurity" && \
  cd ModSecurity && \
  git submodule init && \
  git submodule update && \
  ./build.sh && \
  ./configure && \
  make -j$(nproc) && \
  make install && \
  echo "delete modsecurity archive and strip libmodsecurity (~130mb + ~70mb)" && \
  rm /usr/local/modsecurity/lib/libmodsecurity.a && \
  strip /usr/local/modsecurity/lib/libmodsecurity.so && \
  echo "build nginx modules" && \
  cd /src && \
#  CONFARGS=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p') && \
  MODSECURITYDIR="$(pwd)/ModSecurity-nginx" && \
  cd ./nginx-$NGINX_VERSION && \
  ./configure --with-compat $CONFARGS --add-dynamic-module=$MODSECURITYDIR && \
  make modules && \
  cp objs/ngx_http_modsecurity_module.so /usr/lib/nginx/modules && \
  echo "configure modsecurity" && \
  mkdir -p /etc/nginx/modsec/conf.d && \
  echo "# Example placeholder" > /etc/nginx/modsec/conf.d/example.conf && \

  echo "# Include the recommended configuration" >> /etc/nginx/modsec/main.conf && \
  echo "Include /etc/nginx/modsec/modsecurity.conf" >> /etc/nginx/modsec/main.conf && \
  echo "# User generated" >> /etc/nginx/modsec/main.conf && \
  echo "Include /etc/nginx/modsec/conf.d/*.conf" >> /etc/nginx/modsec/main.conf && \
  echo "" >> /etc/nginx/modsec/main.conf && \
  echo "# OWASP CRS v${MODSECURITY} rules" >> /etc/nginx/modsec/main.conf && \
  echo "Include /usr/local/coreruleset-${OWASPCRS_VERSION}/crs-setup.conf" >> /etc/nginx/modsec/main.conf && \
  echo "Include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/*.conf" >> /etc/nginx/modsec/main.conf && \

  echo "# For inclusion and centralized control" >> /etc/nginx/modsec/modsec_on.conf && \
  echo "modsecurity on;" >> /etc/nginx/modsec/modsec_on.conf && \

  echo "# For inclusion and centralized control" >> /etc/nginx/modsec/modsec_rules.conf && \
  echo "modsecurity_rules_file /etc/nginx/modsec/modsec_includes.conf;" >> /etc/nginx/modsec/modsec_rules.conf && \

  echo "# For inclusion and centralized control" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /etc/nginx/modsec/modsecurity.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/crs-setup.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-901-INITIALIZATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-905-COMMON-EXCEPTIONS.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-910-IP-REPUTATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-911-METHOD-ENFORCEMENT.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-912-DOS-PROTECTION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-913-SCANNER-DETECTION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-920-PROTOCOL-ENFORCEMENT.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-921-PROTOCOL-ATTACK.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-930-APPLICATION-ATTACK-LFI.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-931-APPLICATION-ATTACK-RFI.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-932-APPLICATION-ATTACK-RCE.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-933-APPLICATION-ATTACK-PHP.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-941-APPLICATION-ATTACK-XSS.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-942-APPLICATION-ATTACK-SQLI.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-949-BLOCKING-EVALUATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-950-DATA-LEAKAGES.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-951-DATA-LEAKAGES-SQL.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-952-DATA-LEAKAGES-JAVA.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-953-DATA-LEAKAGES-PHP.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-954-DATA-LEAKAGES-IIS.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-959-BLOCKING-EVALUATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-980-CORRELATION.conf" >> /etc/nginx/modsec/modsec_includes.conf && \
  echo "include /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf" >> /etc/nginx/modsec/modsec_includes.conf && \

  mv /src/unicode.mapping /etc/nginx/modsec && \
  mv /src/modsecurity.conf /etc/nginx/modsec && \
  sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/nginx/modsec/modsecurity.conf && \
  sed -i 's!SecAuditLog /var/log/modsec_audit.log!SecAuditLog /var/log/nginx/modsec_audit.log!g' /etc/nginx/modsec/modsecurity.conf && \
  mv /src/coreruleset-${OWASPCRS_VERSION} /usr/local/ && \
  mv /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf && \
  mv /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example /usr/local/coreruleset-${OWASPCRS_VERSION}/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf && \
  mv /usr/local/coreruleset-${OWASPCRS_VERSION}/crs-setup.conf.example /usr/local/coreruleset-${OWASPCRS_VERSION}/crs-setup.conf && \
  echo "clean all after build" && \
  cd / && \
  apk del .build-deps && \
  rm -rf /src && \
  rm -f /usr/local/nginx/sbin/nginx && \
  rm /etc/nginx/conf.d/default.conf && \
  echo "add modsecurity dependency, certbot & openssl" && \
  apk add libstdc++ yajl libmaxminddb certbot luajit openssl && \
  pip3 install --no-cache-dir certbot-nginx && \
  echo -e "#!/usr/bin/env sh\n\nif [ -f "/usr/bin/certbot" ]; then\n  /usr/bin/certbot renew\nfi\n" > /etc/periodic/daily/certrenew && \
  chmod 755 /etc/periodic/daily/certrenew && \
  rm -rf /var/cache/apk/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf /etc/nginx/conf.d/default.conf
COPY certbot.default.sh /usr/local/sbin/
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 80
EXPOSE 443
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]