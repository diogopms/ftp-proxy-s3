# ftp-proxy-s3

[![CI](https://github.com/diogopms/ftp-proxy-s3/actions/workflows/ci.yml/badge.svg)](https://github.com/diogopms/ftp-proxy-s3/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An FTP/SFTP server that exposes an **Amazon S3 bucket** as its storage backend.
The bucket is mounted with [`s3fs-fuse`](https://github.com/s3fs-fuse/s3fs-fuse)
and served over FTP/SFTP by [`vsftpd`](https://security.appspot.com/vsftpd.html),
all supervised by [`supervisord`](http://supervisord.org/) inside a single
Docker container.

It is handy when a partner or device can only talk FTP/SFTP, but you want the
data to land in S3.

## How it works

```
              ┌──────────────────────── Docker container ───────────────────────┐
              │  supervisord                                                     │
  FTP/SFTP    │   ├─ s3-fuse.sh ──── mounts s3://$FTP_BUCKET → /home/aws/s3bucket │
  client ───► │   ├─ vsftpd ──────── serves /home/aws/s3bucket/ftp-users         │ ───► S3
  :21 + PASV  │   └─ add_users… ──── polls s3://$CONFIG_BUCKET/env.list for users │
              └──────────────────────────────────────────────────────────────────┘
```

- Each FTP user gets a chrooted home under `ftp-users/<user>/files`.
- Users are defined in the `USERS` environment variable and can be live-reloaded
  from a config bucket (see [Live reload](#live-reloading-users)).

## Quick start

### 1. Configure

Copy the example environment file and fill it in:

```bash
cp env.list.example env.list
```

See [Environment variables](#environment-variables) for every option.

### 2. Run

Pull the published image from GHCR (or build it yourself — see
[Building](#building-locally)):

```bash
docker run --rm \
  -p 21:21 \
  -p 30000-30100:30000-30100 \
  --env-file env.list \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  --name ftp-proxy-s3 \
  ghcr.io/diogopms/ftp-proxy-s3:latest
```

- `--cap-add SYS_ADMIN --device /dev/fuse` let `s3fs` create the FUSE mount.
- `--security-opt apparmor:unconfined` is required on hosts whose default
  AppArmor profile blocks FUSE mounts (see [Troubleshooting](#troubleshooting)).
- To restart automatically after a host reboot, add `--restart=always`.

> If you prefer not to grant individual capabilities you can use
> `--privileged` instead of `--cap-add`/`--device`/`--security-opt`, but that is
> broader than necessary.

### Docker Compose

A ready-to-edit [`docker-compose.yml`](docker-compose.yml) is included:

```bash
docker compose up -d
```

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `FTP_BUCKET` | **yes** | S3 bucket mounted as the FTP/SFTP storage. |
| `USERS` | **yes** | Space-separated `username:password` pairs (see [Users & passwords](#users--passwords)). |
| `PASV_ADDRESS` | yes¹ | Public IP/host advertised for FTP passive mode. |
| `CONFIG_BUCKET` | no | Bucket holding an `env.list` file used to [live-reload users](#live-reloading-users). |
| `IAM_ROLE` | no² | Name of the EC2 instance IAM role used to access S3. |
| `AWS_ACCESS_KEY_ID` | no² | AWS access key (only when `IAM_ROLE` is not used). |
| `AWS_SECRET_ACCESS_KEY` | no² | AWS secret key (only when `IAM_ROLE` is not used). |

¹ `PASV_ADDRESS` is auto-detected from the EC2 instance metadata when running on
EC2; otherwise it must be set explicitly.

² Provide **either** an `IAM_ROLE` **or** an `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` pair.

## Users & passwords

`USERS` is a space-separated list of `username:password` entries, for example:

```
USERS=alice:$1$xyz... bob:$1$abc...
```

Passwords are expected to be **hashed** (they are fed to `chpasswd -e`). Generate
a hash with, for example:

```bash
openssl passwd -1 'your-password'      # MD5-crypt
# or
mkpasswd --method=sha-512 'your-password'
```

If you would rather store plaintext passwords, drop the `-e` flag from the
`chpasswd` call in `users.sh`.

### SFTP key access

Each user also gets a `~/.ssh/authorized_keys` file provisioned with the right
permissions, so public-key SFTP access can be used in addition to passwords.

## Live-reloading users

If `CONFIG_BUCKET` is set, the container periodically downloads
`s3://$CONFIG_BUCKET/env.list` and reconciles the user list — adding new users
and updating passwords without a restart. It also repairs ownership/permissions
on files that were uploaded to the bucket directly (e.g. through the S3 console),
which would otherwise be unreadable by the FTP user.

## Building locally

```bash
docker build -t ftp-proxy-s3 .
```

The image is based on `debian:bookworm-slim` and installs `s3fs`, `vsftpd`,
`supervisor` and `awscli` from the Debian repositories.

## Encryption (FTPS)

The server offers **FTPS** (explicit TLS over FTP) but does not require it, so
existing plain-FTP and SFTP clients keep working. The image ships a self-signed
"snakeoil" certificate as a placeholder.

- **Use a real certificate** in production by bind-mounting it over the defaults:
  ```bash
  -v /path/fullchain.pem:/etc/ssl/certs/ssl-cert-snakeoil.pem:ro \
  -v /path/privkey.pem:/etc/ssl/private/ssl-cert-snakeoil.key:ro
  ```
- **To require encryption**, set `force_local_logins_ssl=YES` and
  `force_local_data_ssl=YES` in `vsftpd.conf` and rebuild.

## Troubleshooting

- **`s3fs` fails to mount / container exits immediately.** The host's AppArmor
  profile is likely blocking the FUSE mount. Run with
  `--security-opt apparmor:unconfined` (already shown above). Make sure
  `--cap-add SYS_ADMIN` and `--device /dev/fuse` are present too.
- **Mount point not empty.** `s3fs` is mounted with the `nonempty` option so it
  can mount over a directory that already contains files.
- **Passive transfers hang / time out.** Ensure the `30000-30100` range is
  published (`-p 30000-30100:30000-30100`) and that `PASV_ADDRESS` is the
  address the client can actually reach.

## Releases

Versioned images are published to the GitHub Container Registry:
`ghcr.io/diogopms/ftp-proxy-s3`. Releases are cut automatically once a day from
`master` using [semantic-release](https://semantic-release.gitbook.io/) based on
[Conventional Commits](https://www.conventionalcommits.org/); see
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Diogo Serrano
