#!/bin/sh
# Restores ONLY the minimum required permission. Not AdministratorAccess,
# not a wildcard — the exact same policy provisioned at baseline.
set -e
mc alias set local http://minio:9000 minioadmin minioadmin123
mc admin policy create local task-role-policy /policies/minimum-required.json \
  || mc admin policy update local task-role-policy /policies/minimum-required.json
mc admin policy attach local task-role-policy --user TASKROLEACCESSKEY01
echo "FIXED: task-role-policy restored to minimum-required.json"
