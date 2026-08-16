#!/bin/sh
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    exit 0
fi

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    echo "error: App Store archives must run in Xcode Cloud" >&2
    exit 1
fi

: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud did not provide the repository path}"
: "${CI_TAG:?Xcode Cloud release archives require a Git tag}"
: "${CI_BUILD_NUMBER:?Xcode Cloud did not provide a build number}"
: "${CI_PRODUCT_PLATFORM:?Xcode Cloud did not provide the product platform}"
: "${CI_XCODE_SCHEME:?Xcode Cloud did not provide the Xcode scheme}"
: "${CI_BUNDLE_ID:?Xcode Cloud did not provide the product bundle ID}"
: "${CI_TEAM_ID:?Xcode Cloud did not provide the Apple Developer Team ID}"

if ! printf '%s\n' "${CI_TAG}" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo "error: release tag must use vX.Y.Z: ${CI_TAG}" >&2
    exit 1
fi
if ! printf '%s\n' "${CI_BUILD_NUMBER}" | grep -Eq '^[1-9][0-9]*$'; then
    echo "error: CI_BUILD_NUMBER must be a positive integer: ${CI_BUILD_NUMBER}" >&2
    exit 1
fi
if [ "${CI_PRODUCT_PLATFORM}" != "iOS" ] || \
   [ "${CI_XCODE_SCHEME}" != "Youyaku" ] || \
   [ "${CI_BUNDLE_ID}" != "com.hinoshiba.youyaku" ] || \
   [ "${CI_TEAM_ID}" != "94HVVWXLK3" ]; then
    echo "error: Xcode Cloud release product, scheme, bundle ID, platform, or team is misconfigured" >&2
    exit 1
fi

cd "${CI_PRIMARY_REPOSITORY_PATH}/ios"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Youyaku/Info.plist)" != '$(MARKETING_VERSION)' ] || \
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Youyaku/Info.plist)" != '$(CURRENT_PROJECT_VERSION)' ]; then
    echo "error: Youyaku Info.plist must inherit its version and build from Xcode settings" >&2
    exit 1
fi
TAG_VERSION="${CI_TAG#v}"
PROJECT_VERSION="$(awk -F'"' '/^[[:space:]]*MARKETING_VERSION:/ { print $2; exit }' project.yml)"
if [ -z "${PROJECT_VERSION}" ] || [ "${TAG_VERSION}" != "${PROJECT_VERSION}" ]; then
    echo "error: tag version ${TAG_VERSION} does not match MARKETING_VERSION ${PROJECT_VERSION:-<missing>}" >&2
    exit 1
fi

GENERATED_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
    Youyaku.xcodeproj/project.pbxproj | sort -u)"
if [ "${GENERATED_VERSION}" != "${TAG_VERSION}" ]; then
    echo "error: checked-in Xcode project version ${GENERATED_VERSION:-<missing>} does not match tag ${CI_TAG}" >&2
    exit 1
fi

PROJECT_FILE="Youyaku.xcodeproj/project.pbxproj"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\\1${CI_BUILD_NUMBER};/g" "${PROJECT_FILE}"
APPLIED_BUILD_NUMBER="$(sed -n \
    's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' \
    "${PROJECT_FILE}" | sort -u)"
if [ "${APPLIED_BUILD_NUMBER}" != "${CI_BUILD_NUMBER}" ]; then
    echo "error: failed to apply CI_BUILD_NUMBER to ${PROJECT_FILE}" >&2
    exit 1
fi
