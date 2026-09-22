#!/usr/bin/env bash

set -euo pipefail

image_ref="${1:?usage: test-custom-pgbouncer-image.sh <image-ref>}"
mock_dir="$(mktemp -d)"
trap 'rm -rf "${mock_dir}"' EXIT
chmod 755 "${mock_dir}"

: > "${mock_dir}/userlist.txt"
chmod 644 "${mock_dir}/userlist.txt"

run_in_container() {
  local script="$1"

  docker run --rm \
    --user 0:0 \
    --entrypoint /bin/sh \
    -e PGHOST=mock-postgres \
    -e PGPORT=5432 \
    -e PGUSER=pooler \
    -e PGSCHEMA=public \
    -e INFRASTRUCTURE_ROLES=pooler \
    -e CONNECTION_POOLER_MODE=session \
    -e CONNECTION_POOLER_PORT=6432 \
    -e CONNECTION_POOLER_DEFAULT_SIZE=20 \
    -e CONNECTION_POOLER_RESERVE_SIZE=5 \
    -e CONNECTION_POOLER_MAX_CLIENT_CONN=100 \
    -e CONNECTION_POOLER_MAX_DB_CONN=50 \
    -v "${mock_dir}:/mock:ro" \
    "${image_ref}" \
    -ceu "${script}"
}

echo "Generating PgBouncer configuration"
run_in_container '
  cp /entrypoint.sh /tmp/entrypoint.sh
  sed -i "/^exec \/bin\/pgbouncer /d" /tmp/entrypoint.sh
  cp /mock/userlist.txt /etc/pgbouncer/userlist.txt
  /bin/sh /tmp/entrypoint.sh
  grep -Fx "ignore_startup_parameters = extra_float_digits,options.schema" /etc/pgbouncer/pgbouncer.ini
'

echo "Validating PgBouncer accepts the generated configuration"
run_in_container '
  cp /entrypoint.sh /tmp/entrypoint.sh
  sed -i "/^exec \/bin\/pgbouncer /d" /tmp/entrypoint.sh
  cp /mock/userlist.txt /etc/pgbouncer/userlist.txt
  /bin/sh /tmp/entrypoint.sh
  set +e
  timeout 5s /bin/pgbouncer -v /etc/pgbouncer/pgbouncer.ini >/tmp/pgbouncer.log 2>&1
  status=$?
  set -e
  if [ "${status}" -ne 124 ]; then
    cat /tmp/pgbouncer.log
    exit 1
  fi
'

echo "Image verification passed"
