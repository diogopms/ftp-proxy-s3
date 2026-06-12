# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Instead, report vulnerabilities privately through GitHub's
[security advisories](https://github.com/diogopms/ftp-proxy-s3/security/advisories/new)
("Report a vulnerability"). You can expect an initial response within a few days.

## Supported versions

Only the latest released image (`ghcr.io/diogopms/ftp-proxy-s3:latest`) is
maintained. Older tags are not patched.

## Operational security notes

This project runs an FTP/SFTP front-end over an S3 bucket; please keep the
following in mind when deploying it:

- **Prefer an IAM role** (`IAM_ROLE`) over static `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` credentials. When static keys are used they are written
  to `~/.passwd-s3fs` (mode `600`) inside the container; scope them to the single
  bucket with least privilege.
- **Use FTPS/SFTP and a real certificate.** The image ships with the Debian
  snakeoil certificate as a placeholder — replace it for production and require
  encryption.
- **Keep `env.list` out of version control** (it is already git-ignored) and out
  of the image build context (it is in `.dockerignore`).
- **Restrict the exposed ports** (`21`, `30000-30100`) with a security group or
  firewall to the clients that need them.
- The container needs `SYS_ADMIN` + `/dev/fuse` (and often
  `--security-opt apparmor:unconfined`) for the FUSE mount; grant these instead
  of full `--privileged` where possible.
