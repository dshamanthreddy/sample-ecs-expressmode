FROM nginx:1.27-alpine

# Remove the default config and add our own
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Static content served by Nginx
COPY html/ /usr/share/nginx/html/

EXPOSE 80

# Lightweight container healthcheck (matches the ALB health check path)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:80/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
