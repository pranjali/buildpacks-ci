#!/usr/bin/env bash
# shellcheck disable=SC2086

set -euo pipefail
if [ "$ALLOW_FAILURE" = true ] ; then #This script runs before and after deployment so if the env is not deployed yet this script can fail
  set +e
fi

set +x
eval "$(bbl --state-dir bbl-state/${ENV_NAME} print-env)"
cf_password=$(credhub get -n /bosh-${ENV_NAME}/cf/cf_admin_password -j | jq -r .value)

target="api.$ENV_NAME.buildpacks-gcp.ci.cf-app.com"

cf api "$target" --skip-ssl-validation || (sleep 4 && cf api "$target" --skip-ssl-validation)

cf auth admin "$cf_password" || (sleep 4 && cf auth admin "$cf_password")
set -x

custom_buildpacks=$(cf buildpacks | tail -n +4 | awk '{ print $1,$6 }' | grep -v 'apt_buildpack\|binary_buildpack\|credhub_buildpack\|dotnet_core_buildpack\|go_buildpack\|nginx_buildpack\|nodejs_buildpack\|php_buildpack\|python_buildpack\|r_buildpack\|ruby_buildpack\|staticfile_buildpack\|java_buildpack\|hwc_buildpack' | grep 'cflinuxfs2\|cflinuxfs3\|windows' || true)

echo "$custom_buildpacks" | while read -r bp_and_stack; do
  bp=$(echo $bp_and_stack | cut -d ' ' -f1)
  stack=$(echo $bp_and_stack | cut -d ' ' -f2)
  cf delete-buildpack "$bp" -s "$stack" -f
done

null_buildpacks=$(cf buildpacks | tail -n +4 | grep -v 'cflinuxfs2\|cflinuxfs3\|windows' | cut -d ' ' -f1 || true)

for bp in $null_buildpacks; do
  cf delete-buildpack "$bp" -f -s ""
done
