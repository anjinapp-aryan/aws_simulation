#!/bin/sh
# Simulates a real IAM misconfiguration: replaces the task-role policy with
# one missing s3:PutObject. This is a real MinIO admin policy change,
# evaluated live on the next request — no credential reissue needed.
set -e
mc alias set local http://minio:9000 minioadmin minioadmin123
mc admin policy create local task-role-policy /policies/broken-missing-putobject.json \
  || mc admin policy update local task-role-policy /policies/broken-missing-putobject.json
mc admin policy attach local task-role-policy --user TASKROLEACCESSKEY01
echo "BROKEN: task-role-policy now missing s3:PutObject"
