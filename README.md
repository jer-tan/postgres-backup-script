# PostgreSQL Backup Script with S3 Upload

This script automates PostgreSQL database backups, compresses them, and optionally uploads them to an S3-compatible storage (e.g., AWS S3, Cloudflare R2). It supports multiple backup jobs configured via a single JSON file.

## ✨ Features

- Backup multiple PostgreSQL databases.
- Retry failed backups up to 5 times.
- Upload to AWS S3 or any S3-compatible service.
- Automatic cleanup of old local backups.

## 🛂 Requirements

- `bash`
- [`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html)
- [`jq`](https://stedolan.github.io/jq/)
- [`aws` CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

## ⚙️ Configuration

Create a `config.json` file in the same directory with the following structure:

```json
[
  {
    "database_url": "postgresql://username:password@host:port/database",
    "backup_dir": "/path/to/local/backup/folder",
    "retention_days": 7,
    "s3_bucket": "your-s3-bucket-name",
    "aws_access_key_id": "YOUR_AWS_ACCESS_KEY_ID",
    "aws_secret_access_key": "YOUR_AWS_SECRET_ACCESS_KEY",
    "aws_region": "us-east-1",
    "s3_endpoint_url": "https://<optional-s3-endpoint>" // Optional for R2, MinIO, etc.
  }
]
```

You can add multiple entries in the array to back up multiple databases.

## 🏃 Usage

Make the script executable:

```bash
chmod +x backup.sh
```

Then run:

```bash
./backup.sh
```


## Behavior

- Dumps the database into a gzipped `.sql.gz` file in `backup_dir`.
- Retries up to 5 times if the `pg_dump` fails.
- Uploads the backup to the specified S3 bucket (if provided).
- Deletes backups older than `retention_days`.

## Example Output

```
=== Starting backup job 1/1 ===
Backing up database 'railway' to /home/user/backups/railway_20250524_152149.sql.gz ...
Backup created: /home/user/backups/railway_20250524_152149.sql.gz
Uploading to s3://my-database-backups/railway_20250524_152149.sql.gz ...
Upload successful
Deleting local backups older than 7 days in /home/user/backups ...
=== Finished backup job 1/1 ===
```
## ⏰ Scheduling via Cron
To run the backup daily at 2:00 AM:

```bash
crontab -e
```
Add the line:
```bash
0 2 * * * /path/to/backup.sh >> /path/to/backup.log 2>&1
```

## ⚠️ Notes

- If `aws_access_key_id` or `aws_secret_access_key` are omitted, the script will use the default AWS credentials configured in your environment.
- If you don’t want to upload to S3, simply omit the `s3_bucket` field.
