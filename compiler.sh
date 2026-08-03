#!/usr/bin/env bash
# =============================================================================
# compiler.sh
# Builds plasma-login-manager as a .deb for Soplos Linux Tyson
# Debian forky/testing - Wayland only
#
# Usage: ./compiler.sh [VERSION]
#        ./compiler.sh           -> builds VERSION_DEFAULT
#        ./compiler.sh 6.7.2     -> builds that specific release
#
# Result: <project directory>/plasma-login-manager_<VERSION>-soplos_amd64.deb
#
# Notes:
#   - Can be built on any Soplos with a forky base, Tyron included: the build
#     dependencies come from Debian, not from the desktop in use.
#   - Do NOT install the .deb on Tyron or on any machine that does not run
#     Plasma: the postinst takes over display-manager.service and starts
#     plasmalogin, leaving the machine without a graphical login. Test only
#     on Tyson.
#   - Needs an internet connection to fetch the source and the build deps.
#   - The build tree is kept on purpose so a failed run can be inspected and
#     a rebuild does not download the tarball again.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
VERSION_DEFAULT="6.7.2"
VERSION="${1:-$VERSION_DEFAULT}"
REVISION="1-soplos"

# Directory of this script. The debian/ that gets packaged comes from here, so
# what is built is always what is versioned in the project.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source: the official release tarball. Using the tarball rather than a git
# checkout is the KDE-supported way of building a release, and it is the one
# guaranteed to carry the po/ directory.
UPSTREAM_BASE="https://download.kde.org/stable/plasma/${VERSION}"
TARBALL_NAME="plasma-login-manager-${VERSION}.tar.xz"

BUILD_ROOT="${HOME}/plasma-login-build"
BUILD_DIR="${BUILD_ROOT}/plasma-login-manager-${VERSION}"

# Packaging tools. Left installed on purpose: removing them pulls half the
# toolchain out with autoremove and the next build has to fetch it again.
PACKAGING_TOOLS=(
    devscripts
    equivs
)

# -----------------------------------------------------------------------------
# COLOURS
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# -----------------------------------------------------------------------------
# LOG
# Everything on screen is also written to a file, so a failure halfway through
# a long build does not depend on the terminal scrollback.
# -----------------------------------------------------------------------------
LOG="${HOME}/plasma-login-build-${VERSION}.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

on_exit() {
    local code=$?
    echo ""
    if [ "$code" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Build failed (exit ${code})."
        echo -e "${RED}[ERROR]${NC} Full log: ${LOG}"
    else
        echo -e "${GREEN}[INFO]${NC} Full log: ${LOG}"
    fi
}
trap on_exit EXIT

info "Building version: ${VERSION}-${REVISION}"
info "Log: ${LOG}"

# -----------------------------------------------------------------------------
# 1. CHECK THE PROJECT debian/ TREE
# Without it there is no packaging worth the name: an earlier revision of this
# script generated a degraded one on the fly and produced a .deb that installed
# but never took over the display manager.
# -----------------------------------------------------------------------------
for f in control rules changelog copyright postinst prerm postrm source/format \
         pam/plasmalogin pam/plasmalogin-greeter pam/plasmalogin-autologin
do
    [[ -f "${PROJECT_DIR}/debian/${f}" ]] || \
        error "Missing ${PROJECT_DIR}/debian/${f} - the packaging is incomplete."
done
info "Project debian/ tree verified"

# -----------------------------------------------------------------------------
# 2. PACKAGING TOOLS
# -----------------------------------------------------------------------------
info "Installing packaging tools..."
sudo apt install -y "${PACKAGING_TOOLS[@]}"

# -----------------------------------------------------------------------------
# 3. DOWNLOAD THE UPSTREAM SOURCE
# -----------------------------------------------------------------------------
mkdir -p "${BUILD_ROOT}"
cd "${BUILD_ROOT}"

if [[ -f "${TARBALL_NAME}" ]]; then
    info "Tarball already present, reusing ${TARBALL_NAME}"
else
    info "Downloading ${TARBALL_NAME}..."
    curl -fsSL -O "${UPSTREAM_BASE}/${TARBALL_NAME}" \
        || error "Could not download ${UPSTREAM_BASE}/${TARBALL_NAME} - check that the version exists."
    curl -fsSL -O "${UPSTREAM_BASE}/${TARBALL_NAME}.sig" \
        || warn "Could not download the signature. Continuing without verifying it."
fi

# Signature check only when gpg already holds the KDE release key. Not fatal:
# requiring the KDE keyring on every build machine is not worth it.
if [[ -f "${TARBALL_NAME}.sig" ]] && command -v gpg >/dev/null 2>&1; then
    if gpg --verify "${TARBALL_NAME}.sig" "${TARBALL_NAME}" >/dev/null 2>&1; then
        info "  GPG signature verified"
    else
        warn "  Could not verify the signature (KDE release key missing from the keyring)."
    fi
fi

info "Extracting source..."
rm -rf "${BUILD_DIR}"
tar xf "${TARBALL_NAME}"
[[ -d "${BUILD_DIR}" ]] || error "The tarball does not contain ${BUILD_DIR}"
cd "${BUILD_DIR}"

# Translations are installed by CMake on its own through ki18n_install(po).
# If po/ is absent the greeter ends up English-only, and it is better to know
# that before building than after installing.
if [[ -d po ]]; then
    info "  Translations found: $(find po -mindepth 1 -maxdepth 1 -type d | wc -l) languages"
else
    warn "  Source has NO po/ directory - the greeter will be English only."
fi

# -----------------------------------------------------------------------------
# 4. IMPORT THE PROJECT debian/ TREE
# Copied verbatim from the project. Nothing is generated on the fly: what gets
# built is what is versioned and reviewed.
# -----------------------------------------------------------------------------
info "Copying debian/ from ${PROJECT_DIR}..."
rm -rf debian
cp -a "${PROJECT_DIR}/debian" .
chmod +x debian/rules

# The changelog version drives the name of the resulting .deb.
CHANGELOG_VERSION="$(dpkg-parsechangelog -l debian/changelog -S Version)"
if [[ "${CHANGELOG_VERSION}" != "${VERSION}-${REVISION}" ]]; then
    error "debian/changelog declares ${CHANGELOG_VERSION} but ${VERSION}-${REVISION} was requested. Update the changelog."
fi
info "  debian/changelog matches the requested version"

# -----------------------------------------------------------------------------
# 4b. SOPLOS TRANSLATIONS
# Upstream ships no European Portuguese catalogue, only pt_BR. Anything under
# po/ in this project is copied into the source tree before building, and
# ki18n_install(po) picks it up like any other language, with no change to the
# upstream CMakeLists. Upstream always wins: if a language later appears there,
# the Soplos copy is skipped instead of overwriting it.
# -----------------------------------------------------------------------------
if [[ -d "${PROJECT_DIR}/po" ]]; then
    for lang_dir in "${PROJECT_DIR}"/po/*/; do
        [[ -d "${lang_dir}" ]] || continue
        lang="$(basename "${lang_dir}")"
        if [[ -d "po/${lang}" ]]; then
            warn "  Upstream now ships po/${lang}: keeping theirs, skipping the Soplos one."
        else
            cp -a "${lang_dir}" po/
            info "  Added Soplos translation: ${lang}"
        fi
    done
fi

# -----------------------------------------------------------------------------
# 5. BUILD DEPENDENCIES
# -----------------------------------------------------------------------------
info "Installing build deps from debian/control..."
# Remove any existing build-deps metapackage first. mk-build-deps generates
# the same version as the source package; if it is already installed apt will
# skip it entirely and any newly added Build-Depends will never be installed.
sudo apt-get remove -y plasma-login-manager-build-deps 2>/dev/null || true
sudo mk-build-deps -i -r debian/control -t "apt-get -y --reinstall"

# mk-build-deps can leave dependencies uninstalled without returning an error.
# Without this check the failure surfaces much later, as a CMake NOTFOUND that
# does not say which package is missing.

if ! MISSING_DEPS="$(dpkg-checkbuilddeps debian/control 2>&1)"; then
    error "Missing build dependencies: ${MISSING_DEPS}"
fi
info "  All build dependencies present"

# -----------------------------------------------------------------------------
# 6. BUILD
# The build dir must be clean before every attempt: CMake caches NOTFOUND, and
# with a dirty cache from a failed run the configure step fails again even once
# the cause is gone.
# -----------------------------------------------------------------------------
info "Building plasma-login-manager ${VERSION}..."
rm -rf obj-x86_64-linux-gnu
dpkg-buildpackage -us -uc -b

# -----------------------------------------------------------------------------
# 7. CHECK THE RESULT
# -----------------------------------------------------------------------------
DEB="${BUILD_ROOT}/plasma-login-manager_${VERSION}-${REVISION}_amd64.deb"
[[ -f "${DEB}" ]] || error "Expected .deb not found: ${DEB}"

# KDE installs gettext catalogues (.mo), not Qt Linguist ones (.qm).
MO_COUNT="$(dpkg -c "${DEB}" | grep -c '\.mo$' || true)"
if [[ "${MO_COUNT}" -eq 0 ]]; then
    warn "The package contains NO .mo file: the greeter will be English only."
else
    info "  Translations in the package: ${MO_COUNT} .mo files"
fi

info "Package contents (locales, icons and qml omitted):"
dpkg -c "${DEB}" | grep -vE "locale|/usr/share/icons|qml"

info "Declared dependencies:"
dpkg -I "${DEB}" | grep -E "^ (Depends|Recommends|Conflicts|Replaces|Provides):"

cp -f "${DEB}" "${PROJECT_DIR}/"
info "Package copied to ${PROJECT_DIR}/$(basename "${DEB}")"

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------
echo ""
echo "====================================================================="
info "BUILD COMPLETE"
echo "====================================================================="
echo ""
echo "  Package : ${PROJECT_DIR}/plasma-login-manager_${VERSION}-${REVISION}_amd64.deb"
echo ""
ls -lh "${PROJECT_DIR}/plasma-login-manager_${VERSION}-${REVISION}_amd64.deb" 2>/dev/null
echo ""
warn "BEFORE PUBLISHING:"
echo "  1. Install and test on the Tyson VM (NEVER on Tyron: the postinst"
echo "     takes over display-manager.service and it is left with no"
echo "     graphical login)"
echo "  2. Check that the greeter comes up in the system language"
echo "  3. Check that the System Settings module (KCM) opens without errors"
echo "  4. Upload to the Soplos repository"
echo ""
echo "  Build tree kept at ${BUILD_ROOT}. To reclaim the space:"
echo "      rm -rf ${BUILD_ROOT}"
echo "      sudo apt remove plasma-login-manager-build-deps"
echo ""
echo "====================================================================="
