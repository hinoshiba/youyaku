#!/bin/sh
set -eu

REPOSITORY_PATH="${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"

"${REPOSITORY_PATH}/Scripts/fetch-vendor.sh" --ios
