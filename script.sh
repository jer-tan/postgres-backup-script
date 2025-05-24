#!/bin/bash

CONFIG_FILE="config.json"

# Check dependencies
for cmd in jq pg_dump aws; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

# Number of configs
CONFIG_COUNT=$(jq 'length' "$CONFIG_FILE")

for (( i=0; i<CONFIG_COUNT; i++ )); do
  echo "=== Starting backup job $((i+1))/$CONFIG_COUNT ==="

  # Parse config fields
  DATABASE_URL=$(jq -r ".[$i].database_url" "$CONFIG_FILE")
  BACKUP_DIR=$(jq -r ".[$i].backup_dir" "$CONFIG_FILE")
  RETENTION_DAYS=$(jq -r ".[$i].retention_days // 7" "$CONFIG_FILE")
  S3_BUCKET=$(jq -r ".[$i].s3_bucket" "$CONFIG_FILE")
  AWS_ACCESS_KEY_ID=$(jq -r ".[$i].aws_access_key_id // empty" "$CONFIG_FILE")
  AWS_SECRET_ACCESS_KEY=$(jq -r ".[$i].aws_secret_access_key // empty" "$CONFIG_FILE")
  AWS_REGION=$(jq -r ".[$i].aws_region // empty" "$CONFIG_FILE")
  S3_ENDPOINT_URL=$(jq -r ".[$i].s3_endpoint_url // empty" "$CONFIG_FILE")

  # Validate DATABASE_URL format
  REGEX='^postgres(ql)?:\/\/([^:]+):([^@]+)@([^:]+):([0-9]+)\/(.+)$'
  if [[ $DATABASE_URL =~ $REGEX ]]; then
    DB_USER="${BASH_REMATCH[2]}"
    DB_PASSWORD="${BASH_REMATCH[3]}"
    DB_HOST="${BASH_REMATCH[4]}"
    DB_PORT="${BASH_REMATCH[5]}"
    DB_NAME="${BASH_REMATCH[6]}"
  else
    echo "Invalid database URL format for job $((i+1))"
    continue
  fi

  # Timestamp and filename
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"
  BACKUP_PATH="$BACKUP_DIR/$FILENAME"

  mkdir -p "$BACKUP_DIR"

  echo "Backing up database '$DB_NAME' to $BACKUP_PATH ..."

  export PGPASSWORD="$DB_PASSWORD"

  MAX_RETRIES=5
  RETRY_DELAY=5
  ATTEMPT=1
  DUMP_SUCCESS=false

  while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
    set +e
    pg_dump -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" "$DB_NAME" | gzip > "$BACKUP_PATH"
    PG_DUMP_EXIT_CODE=${PIPESTATUS[0]}
    set -e

    if [[ $PG_DUMP_EXIT_CODE -eq 0 ]]; then
      echo "Backup created: $BACKUP_PATH"
      DUMP_SUCCESS=true
      break
    else
      echo "pg_dump failed (attempt $ATTEMPT/$MAX_RETRIES), retrying in $RETRY_DELAY seconds..."
      ((ATTEMPT++))
      sleep "$RETRY_DELAY"
    fi
  done

  unset PGPASSWORD

  if [[ "$DUMP_SUCCESS" != true ]]; then
    echo "Backup failed after $MAX_RETRIES attempts for job $((i+1)), skipping upload"
    continue
  fi

  # Export AWS credentials if provided
  if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]]; then
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
  fi

  if [[ -n "$AWS_REGION" ]]; then
    export AWS_REGION
  fi

  # Upload to S3 or R2
  if [[ -n "$S3_BUCKET" ]]; then
    echo "Uploading to s3://$S3_BUCKET/$FILENAME ..."
    if [[ -n "$S3_ENDPOINT_URL" ]]; then
      aws --endpoint-url "$S3_ENDPOINT_URL" s3 cp "$BACKUP_PATH" "s3://$S3_BUCKET/$FILENAME"
    else
      aws s3 cp "$BACKUP_PATH" "s3://$S3_BUCKET/$FILENAME"
    fi

    if [ $? -eq 0 ]; then
      echo "Upload successful"
    else
      echo "Upload failed for job $((i+1))"
      continue
    fi
  else
    echo "No S3 bucket configured, skipping upload."
  fi

  # Clean up old backups locally
  echo "Deleting local backups older than $RETENTION_DAYS days in $BACKUP_DIR ..."
  find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -type f -mtime +$RETENTION_DAYS -exec rm -f {} \;

  echo "=== Finished backup job $((i+1))/$CONFIG_COUNT ==="
  echo ""
done

echo "All backup jobs completed."
