#!/bin/sh
# Runs once as the "platform/IAM team": creates the bucket, the task-role
# user (matching the access key vended via ecs-local-endpoints), and attaches
# the minimum-required policy. Idempotent — safe to re-run.
set -e

mc alias set local http://minio:9000 minioadmin minioadmin123

mc mb --ignore-existing local/lab-bucket

mc admin user add local TASKROLEACCESSKEY01 TaskRoleSecretKey123 || true

mc admin policy create local task-role-policy /policies/minimum-required.json \
  || mc admin policy update local task-role-policy /policies/minimum-required.json
mc admin policy attach local task-role-policy --user TASKROLEACCESSKEY01

echo "PROVISIONED: bucket=lab-bucket user=TASKROLEACCESSKEY01 policy=minimum-required.json"
