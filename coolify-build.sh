#!/usr/bin/env bash
set -eEuo pipefail
test "${DEBUG:-}" && set -x

# Override any user-supplied umask that could cause problems, see #1222
umask 002

# Pre-pre-flight? 🤷
if [[ -n "${MSYSTEM:-}" ]]; then
  echo "Seems like you are using an MSYS2-based system (such as Git Bash) which is not supported. Please use WSL instead."
  exit 1
fi

echo "source install/_logging.sh"
source install/_logging.sh

echo "source install/_lib.sh"
source install/_lib.sh


# Login to Docker Hub to avoid rate limiting
# echo "${DOCKER_TOKEN}" | docker login -u "${DOCKER_USERNAME}" --password-stdin


# Pre-flight. No impact yet.

echo "source install/parse-cli.sh"
source install/parse-cli.sh

echo "source install/detect-platform.sh"
source install/detect-platform.sh

echo "Run dc detect script inline"

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  _group="::group::"
  _endgroup="::endgroup::"
else
  _group="▶ "
  _endgroup=""
fi

echo "${_group}Initializing Docker Compose ..."

# To support users that are symlinking to docker-compose
dc_base="$(docker compose version --short &>/dev/null && echo 'docker compose' || echo '')"
dc_base_standalone="$(docker-compose version --short &>/dev/null && echo 'docker-compose' || echo '')"

COMPOSE_VERSION=$([ -n "$dc_base" ] && $dc_base version --short || echo '')
STANDALONE_COMPOSE_VERSION=$([ -n "$dc_base_standalone" ] && $dc_base_standalone version --short || echo '')

if [[ -z "$COMPOSE_VERSION" && -z "$STANDALONE_COMPOSE_VERSION" ]]; then
  echo "FAIL: Docker Compose is required to run self-hosted"
  exit 1
fi

if [[ -z "$COMPOSE_VERSION" ]] || [[ -n "$STANDALONE_COMPOSE_VERSION" ]] && ! vergte ${COMPOSE_VERSION//v/} ${STANDALONE_COMPOSE_VERSION//v/}; then
  COMPOSE_VERSION="${STANDALONE_COMPOSE_VERSION}"
  dc_base="$dc_base_standalone"
fi

if [[ "$(basename $0)" = "coolify-build.sh" ]]; then
  dc="$dc_base --ansi never --env-file ${_ENV}"
else
  dc="$dc_base --ansi never"
fi

proxy_args="--build-arg http_proxy=${http_proxy:-} --build-arg https_proxy=${https_proxy:-} --build-arg no_proxy=${no_proxy:-}"
dcr="$dc run --pull=never --rm > /dev/null"
dcb="$dc build $proxy_args --quiet"
dbuild="docker build $proxy_args --quiet"
echo "$dcr"
echo "${_endgroup}"

# source install/dc-detect-version.sh

echo "source install/error-handling.sh"
source install/error-handling.sh
# We set the trap at the top level so that we get better tracebacks.
trap_with_arg cleanup ERR INT TERM EXIT

echo "source install/check-latest-commit.sh"
source install/check-latest-commit.sh

# source install/check-minimum-requirements.sh

# Let's go! Start impacting things.
# Upgrading clickhouse needs to come first before turning things off, since we need the old clickhouse image
# in order to determine whether or not the clickhouse version needs to be upgraded.

echo "SKIPPING source install/upgrade-clickhouse.sh"
# source install/upgrade-clickhouse.sh

echo "SKIPPING source install/turn-things-off.sh"
# source install/turn-things-off.sh

echo "source install/create-docker-volumes.sh"
source install/create-docker-volumes.sh

echo "source install/ensure-files-from-examples.sh"
source install/ensure-files-from-examples.sh

echo "source install/check-memcached-backend.sh"
source install/check-memcached-backend.sh

# source install/ensure-relay-credentials.sh
ensure_relay_credentials() {
  echo "${_group}Ensuring Relay credentials ..."

  RELAY_CONFIG_YML=relay/config.yml
  RELAY_CREDENTIALS_JSON=relay/credentials.json

  ensure_file_from_example $RELAY_CONFIG_YML

  if [[ -f "$RELAY_CREDENTIALS_JSON" ]]; then
    echo "$RELAY_CREDENTIALS_JSON already exists, skipped creation."
  else

    # There are a couple gotchas here:
    #
    # 1. We need to use a tmp file because if we redirect output directly to
    #    credentials.json, then the shell will create an empty file that relay
    #    will then try to read from (regardless of options such as --stdout or
    #    --overwrite) and fail because it is empty.
    #
    # 2. We pull relay:nightly before invoking `run relay credentials generate`
    #    because an implicit pull under the run causes extra stdout that results
    #    in a garbage credentials.json.
    #
    # 3. We need to use -T to ensure that we receive output on Docker Compose
    #    1.x and 2.2.3+ (funny story about that ... ;). Note that the long opt
    #    --no-tty doesn't exist in Docker Compose 1.

    $dc pull relay
    creds="$dcr --no-deps -T relay credentials"
    $creds generate --stdout >"$RELAY_CREDENTIALS_JSON".tmp
    mv "$RELAY_CREDENTIALS_JSON".tmp "$RELAY_CREDENTIALS_JSON"
    if [ ! -s "$RELAY_CREDENTIALS_JSON" ]; then
      # Let's fail early if creds failed, to make debugging easier.
      echo "Failed to create relay credentials in $RELAY_CREDENTIALS_JSON."
      echo "--- credentials.json v ---------------------------------------"
      cat -v "$RELAY_CREDENTIALS_JSON" || true
      echo "--- credentials.json ^ ---------------------------------------"
      exit 1
    fi
    echo "Relay credentials written to $RELAY_CREDENTIALS_JSON."
  fi

  echo "${_endgroup}"
}

echo "ensure_relay_credentials"
ensure_relay_credentials

echo "source install/generate-secret-key.sh"
source install/generate-secret-key.sh

echo "source install/update-docker-images.sh"
source install/update-docker-images.sh

# source install/build-docker-images.sh

build_docker_images() {
  echo "${_group}Building and tagging Docker images ..."

  echo ""
  # Build any service that provides the image sentry-self-hosted-local first,
  # as it is used as the base image for sentry-cleanup-self-hosted-local.
  # $dcb --force-rm web

  echo "Building web"
  $dcb web

  # Build each other service individually to localize potential failures better.
  for service in $($dc config --services); do
    echo "Building $service"
    $dcb --force-rm "$service"
  done
  echo ""
  echo "Docker images built."
  echo "${_endgroup}"
}

echo "build_docker_images"
build_docker_images

echo "source install/bootstrap-snuba.sh"
source install/bootstrap-snuba.sh

echo "source install/upgrade-postgres.sh"
source install/upgrade-postgres.sh

echo "source install/ensure-correct-permissions-profiles-dir.sh"
source install/ensure-correct-permissions-profiles-dir.sh

echo "source install/set-up-and-migrate-database.sh"
source install/set-up-and-migrate-database.sh

echo "source install/geoip.sh"
source install/geoip.sh

echo "source install/setup-js-sdk-assets.sh"
source install/setup-js-sdk-assets.sh

echo "source install/wrap-up.sh"
source install/wrap-up.sh
