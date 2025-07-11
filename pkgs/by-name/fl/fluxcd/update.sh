#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl gnugrep gnused jq

set -x -eu -o pipefail

NIXPKGS_PATH="$(git rev-parse --show-toplevel)"
FLUXCD_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

OLD_VERSION="$(nix-instantiate --eval -E "with import $NIXPKGS_PATH {}; fluxcd.version or (builtins.parseDrvName fluxcd.name).version" | tr -d '"')"
LATEST_TAG=$(curl ${GITHUB_TOKEN:+" -u \":$GITHUB_TOKEN\""} --silent https://api.github.com/repos/fluxcd/flux2/releases/latest | jq -r '.tag_name')
LATEST_VERSION=$(echo "${LATEST_TAG}" | sed 's/^v//')

if [ ! "$OLD_VERSION" = "$LATEST_VERSION" ]; then
    SRC_SHA256=$(nix-prefetch-url --quiet --unpack "https://github.com/fluxcd/flux2/archive/refs/tags/${LATEST_TAG}.tar.gz")
    SRC_HASH=$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$SRC_SHA256")
    MANIFESTS_SHA256=$(nix-prefetch-url --quiet --unpack "https://github.com/fluxcd/flux2/releases/download/${LATEST_TAG}/manifests.tar.gz")
    MANIFESTS_HASH=$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$MANIFESTS_SHA256")

    setKV () {
        sed -i "s|$1 = \".*\"|$1 = \"${2:-}\"|" "${FLUXCD_PATH}/package.nix"
    }

    setKV version "${LATEST_VERSION}"
    setKV srcHash "${SRC_HASH}"
    setKV manifestsHash "${MANIFESTS_HASH}"
    setKV vendorHash "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" # The same as lib.fakeHash

    set +e
    VENDOR_SHA256=$(nix-build --no-out-link -A fluxcd "$NIXPKGS_PATH" 2>&1 >/dev/null | grep "got:" | cut -d':' -f2 | sed 's| ||g')
    VENDOR_HASH=$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$VENDOR_SHA256")
    set -e

    if [ -n "${VENDOR_HASH:-}" ]; then
        setKV vendorHash "${VENDOR_HASH}"
    else
        echo "Update failed. VENDOR_HASH is empty."
        exit 1
    fi

    # `git` flag here is to be used by local maintainers to speed up the bump process
    if [ $# -eq 1 ] && [ "$1" = "git" ]; then
        git switch -c "package-fluxcd-${LATEST_VERSION}"
        git add "$FLUXCD_PATH"/package.nix
        git commit -m "fluxcd: ${OLD_VERSION} -> ${LATEST_VERSION}

Release: https://github.com/fluxcd/flux2/releases/tag/v${LATEST_VERSION}"
    fi
else
    echo "fluxcd is already up-to-date at $OLD_VERSION"
fi
