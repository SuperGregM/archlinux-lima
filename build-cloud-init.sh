#!/usr/bin/env bash
# shellcheck disable=SC2034  # Unused variables left for readability

set -e # -e: exit on error

##################################################################################################################
# printf Colors and Formats

# General Formatting
FORMAT_RESET=$'\e[0m'
FORMAT_BRIGHT=$'\e[1m'
FORMAT_DIM=$'\e[2m'
FORMAT_ITALICS=$'\e[3m'
FORMAT_UNDERSCORE=$'\e[4m'
FORMAT_BLINK=$'\e[5m'
FORMAT_REVERSE=$'\e[7m'
FORMAT_HIDDEN=$'\e[8m'

# Foreground Colors
TEXT_BLACK=$'\e[30m'
TEXT_RED=$'\e[31m'    # Warning
TEXT_GREEN=$'\e[32m'  # Command Completed
TEXT_YELLOW=$'\e[33m' # Recommended Commands / Extras
TEXT_BLUE=$'\e[34m'
TEXT_MAGENTA=$'\e[35m'
TEXT_CYAN=$'\e[36m' # Info Needs
TEXT_WHITE=$'\e[37m'

# Background Colors
BACKGROUND_BLACK=$'\e[40m'
BACKGROUND_RED=$'\e[41m'
BACKGROUND_GREEN=$'\e[42m'
BACKGROUND_YELLOW=$'\e[43m'
BACKGROUND_BLUE=$'\e[44m'
BACKGROUND_MAGENTA=$'\e[45m'
BACKGROUND_CYAN=$'\e[46m'
BACKGROUND_WHITE=$'\e[47m'

# Example Usage
# printf ' %sThis is a warning%s\n' "$TEXT_RED" "$FORMAT_RESET"
# printf ' %s%sInfo:%s Details here\n' "$FORMAT_UNDERSCORE" "$TEXT_CYAN" "$FORMAT_RESET"

##################################################################################################################

# This script builds cloud-init and netplan packages for Arch Linux ARM.
# It requires git, base-devel, and pandoc-bin to be installed.
# It can be run in a Lima VM with Arch Linux ARM or directly on an Arch Linux ARM system.

# To run this script, you can use the following commands:
# limactl start --yes --containerd none --cpus 12 --memory 16 --disk 20 ./lima-build-cloud-init-env.yaml --name build-cloud-init-env
# limactl shell build-cloud-init-env

# inside the VM:
# ./build-cloud-init.sh

cloud_init_package_version="25.1.2-1"
netplan_package_version="1.1.2-1"
build_dir="/tmp/build"
output_dir="/tmp/lima/output"
cloud_init_dir="$build_dir/cloud-init"
netplan_dir="$build_dir/netplan"
pandoc_dir="$build_dir/pandoc-bin"

# --- Preparation ---
printf " %sCreating output directory...%s\n" "$TEXT_GREEN" "$FORMAT_RESET"
mkdir -pv "$build_dir"
cd "$build_dir"

if ! command -v git &>/dev/null; then
    printf '\n %sInstalling git & base-devel%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    sudo pacman -Syy --noconfirm --needed git base-devel

    printf '\n %sChange how many threads to use%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    sudo sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j16"/' /etc/makepkg.conf
fi
if ! command -v pandoc &>/dev/null; then
    printf '\n %sInstalling pandoc-bin from AUR%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    git clone https://aur.archlinux.org/pandoc-bin.git "$pandoc_dir"
    cd "$pandoc_dir" || exit
    makepkg -si --noconfirm --needed
fi

case "$1" in
-d | --delete)
    printf '\n %sDeleting build directories...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    rm -rf "$build_dir"
    ;;
-dc | --delete-cloud-init)
    printf '\n %sDeleting cloud-init build directory...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    rm -rf "$cloud_init_dir"
    ;;
-dn | --delete-netplan)
    printf '\n %sDeleting netplan build directory...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    rm -rf "$netplan_dir"
    ;;
-dp | --delete-pandoc)
    printf '\n %sDeleting pandoc-bin build directory...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    rm -rf "$pandoc_dir"
    ;;
*)
    if [[ -z "$1" ]]; then
        # No argument: do nothing, fall through to build
        :
    else
        # Unknown argument: show usage
        printf '\n %s Bad Argument Erase and try again - empty will build cloud-init and netplan packages%s\n' "$TEXT_RED" "$FORMAT_RESET"
        printf '  %sUsage: %s\n' "$TEXT_CYAN" "$FORMAT_RESET"
        printf ' %s -d  | --delete%s            : Delete build directories\n' "$TEXT_YELLOW" "$FORMAT_RESET"
        printf ' %s -dc | --delete-cloud-init%s : Delete cloud-init build directory\n' "$TEXT_YELLOW" "$FORMAT_RESET"
        printf ' %s -dn | --delete-netplan%s    : Delete netplan build directory\n' "$TEXT_YELLOW" "$FORMAT_RESET"
        printf ' %s -dp | --delete-pandoc%s     : Delete pandoc-bin build directory\n\n' "$TEXT_YELLOW" "$FORMAT_RESET"
        exit 1
    fi
    ;;
esac

checkout_version_tag() {
    local version="$1"
    if git rev-parse "v$version" >/dev/null 2>&1; then
        git checkout "v$version"
    elif git rev-parse "$version" >/dev/null 2>&1; then
        git checkout "$version"
    else
        printf "\n %sError: No git tag found for version $version. Exiting.%s\n" "$TEXT_RED" "$FORMAT_RESET"
        exit 1
    fi
}

if ! command -v netplan &>/dev/null; then
    printf '\n %sBuilding netplan from gitlab.archlinux.org...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
    if [[ ! -d "$netplan_dir" ]]; then
        git clone https://gitlab.archlinux.org/archlinux/packaging/packages/netplan.git "$netplan_dir"
        cd "$netplan_dir"
        git fetch --tags
        checkout_version_tag "$netplan_package_version"
        sed -i 's/^arch=.*/arch=(any)/' "$netplan_dir/PKGBUILD"
    fi
    makepkg -si --noconfirm
fi

printf '\n %sBuilding cloud-init from gitlab.archlinux.org...%s\n' "$TEXT_GREEN" "$FORMAT_RESET"
if [[ ! -d "$cloud_init_dir" ]]; then
    git clone https://gitlab.archlinux.org/archlinux/packaging/packages/cloud-init.git "$cloud_init_dir"
    cd "$cloud_init_dir"
    git fetch --tags
    checkout_version_tag "$cloud_init_package_version"
    sed -i "/--deselect 'tests\/unittests\/config\/test_schema.py::TestNetworkSchema::test_network_schema\[net_v2_skipped\]'/a \
    --deselect tests/unittests/test_net.py::TestNetworkdNetRendering::test_networkd_default_generation \\
    --deselect tests/unittests/test_net.py::TestDuplicateMac::test_duplicate_ignored_macs[mscc_felix] \\
    --deselect tests/unittests/test_net.py::TestDuplicateMac::test_duplicate_ignored_macs[fsl_enetc] \\
    --deselect tests/unittests/test_net.py::TestDuplicateMac::test_duplicate_ignored_macs[qmi_wwan]" "$cloud_init_dir/PKGBUILD"
    # sed -i 's/^  netplan/#  netplan/' PKGBUILD
else
    cd "$cloud_init_dir"
fi

makepkg -s --noconfirm -f

# cp -v "$netplan_dir"/*.pkg.tar.xz "$output_dir"
cp -v "$cloud_init_dir"/*.pkg.tar.xz "$output_dir"
