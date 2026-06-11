# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL maintainer="Diogo <info@diogoserrano.com>" \
      org.opencontainers.image.title="ftp-proxy-s3" \
      org.opencontainers.image.description="FTP/SFTP server backed by an S3 bucket mounted with s3fs-fuse" \
      org.opencontainers.image.source="https://github.com/diogopms/ftp-proxy-s3" \
      org.opencontainers.image.licenses="MIT"

# Install runtime packages from the distribution.
# s3fs is shipped by Debian, so we no longer build it from an unpinned git
# checkout; this keeps builds reproducible and drops the C/C++ toolchain
# (and its CVEs) from the final image.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install --no-install-recommends -y \
      awscli \
      ca-certificates \
      curl \
      fuse \
      s3fs \
      supervisor \
      vsftpd \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/aws/s3bucket \
 && echo "/usr/sbin/nologin" >> /etc/shells

# Application scripts
COPY ["s3-fuse.sh", "users.sh", "add_users_in_container.sh", "/usr/local/"]
RUN chmod +x /usr/local/s3-fuse.sh /usr/local/users.sh /usr/local/add_users_in_container.sh

# Service configuration
COPY vsftpd.conf /etc/vsftpd.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 21 = control channel, 30000-30100 = passive data channel range
EXPOSE 21 30000-30100

# Consider the container healthy only while vsftpd is accepting connections.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS --max-time 4 ftp://127.0.0.1:21/ >/dev/null 2>&1 || exit 1

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
