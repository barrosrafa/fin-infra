FROM nginx:1.27-alpine
RUN apk add --no-cache gettext
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /usr/local/bin/staging-gateway-entrypoint
RUN chmod 0755 /usr/local/bin/staging-gateway-entrypoint
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/staging-gateway-entrypoint"]
