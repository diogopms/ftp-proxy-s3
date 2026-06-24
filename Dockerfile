# syntax=docker/dockerfile:1
# Pinned by digest for reproducible builds; Dependabot keeps the digest current.
FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df

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
      ca-certificates \
      curl \
      fuse \
      s3fs \
      ssl-cert \
      supervisor \
      vsftpd \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/aws/s3bucket \
 && echo "/usr/sbin/nologin" >> /etc/shells

# Application scripts
COPY ["s3-fuse.sh", "start-vsftpd.sh", "users.sh", "add_users_in_container.sh", "/usr/local/"]
RUN chmod +x /usr/local/s3-fuse.sh /usr/local/start-vsftpd.sh /usr/local/users.sh /usr/local/add_users_in_container.sh

# Service configuration
COPY vsftpd.conf /etc/vsftpd.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 21 = control channel, 30000-30100 = passive data channel range
EXPOSE 21 30000-30100

# Healthy while vsftpd answers on the control port with its 220 greeting.
# (A plain `curl ftp://` would attempt an anonymous login, which is disabled, so
# it returns failure even when the server is fine — hence the raw banner check.)
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/21 && read -t 4 -u 3 line && [[ $line == 220* ]]"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
