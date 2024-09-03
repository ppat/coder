#!/bin/bash
set -euo pipefail

RELEASES_FILE="$1"
INSTALL_DIR="${2:-"~/.local/bin"}"
RELEASES_TOKEN="${FETCH_GH_TOKEN:-""}"
OWNER="$(id -u)"
GROUP="$(id -g)"
MODE='0755'
if [[ -z "$RELEASES_FILE" ]]; then
  echo "Path to releases file must be provided.!"
  exit 1
fi
if [[ ! -f "$RELEASES_FILE" ]]; then
  echo "$RELEASES_FILE does not exist!"
  exit 1
fi


unpack_archive() {
  local archive_file="$1"
  shift
  # shellcheck disable=SC2124
  local unarchive_opts="$@"

  if [[ "$unarchive_opts" == "null" ]]; then
    unarchive_opts=""
  fi

  echo "Checking file extension..."
  local fileext="${archive_file##*.}"
  if [[ "$fileext" == "gz" || "$fileext" == "tgz" ]]; then
    echo "From tarball..."
    tar -xzv $unarchive_opts -f $archive_file | pr -t -o 4
  elif [[ "$fileext" == "xz" ]]; then
    echo "From xz..."
    tar -xv --xz $unarchive_opts -f $archive_file | pr -t -o 4
  elif [[ "$fileext" == "zip" ]]; then
    echo "From zip file..."
    unzip $unarchive_opts $archive_file | pr -t -o 4
  else
    echo "Assuming asset does not require unpacking..."
  fi
}

install_binary() {
  local source="$1"
  local dest="$INSTALL_DIR/$2"
  local upx_pack="${3:-"pack"}"

  if [[ ! -f "$source" ]]; then
    echo "Source file $source does not exist."
    exit 1
  fi

  echo "Compressing..."
  if [[ "$upx_pack" != "skip" ]]; then
    chmod +x $source
    upx $source 2>&1 | pr -t -o 4
  else
    echo "skipping..."
  fi

  echo "$source -> $dest..."
  sudo install -o $OWNER -g $GROUP -m $MODE $source $dest 2>&1 | pr -t -o 4
}

render_value() {
  # shellcheck disable=SC2124
  local value="$@"
  eval "echo ${value}"
}

install_release() {
  local package_name="$1"
  local release_yaml="$2"

  if [[ -f $INSTALL_DIR/$package_name ]]; then
    echo "Already exists... skipping."
    return
  fi

  # read package configuration from yaml
  local repo="$(yq -e '.[] | select(.name == "'$package_name'") | .repo' $release_yaml)"
  local tag="$(yq -e '.[] | select(.name == "'$package_name'") | .tag' $release_yaml)"
  local asset_regex="$(render_value $(yq -e '.[] | select(.name == "'$package_name'") | .asset_regex' $release_yaml))"
  local asset_files="$(yq -e '.[] | select(.name == "'$package_name'") | .asset_files | @csv' $release_yaml | tail -n +2)"
  local upx_pack="$(yq -e '.[] | select(.name == "'$package_name'") | .upx_pack' $release_yaml 2> /dev/null)"
  local unarchive_opts="$(render_value $(yq -e '.[] | select(.name == "'$package_name'") | .unarchive_opts' $release_yaml 2> /dev/null))"
  local download_dir=$(mktemp -d)

  local fetch_params=""
  if [[ ! -z "$RELEASES_TOKEN" ]]; then
    echo "Downloading (authenticated)..."
    fetch_params="--github-oauth-token=$RELEASES_TOKEN"
  else
    echo "Downloading (unauthenticated)..."
  fi
  fetch --repo=$repo --tag=$tag --release-asset=$asset_regex $fetch_params $download_dir 2>&1 | pr -t -o 4

  pushd $download_dir > /dev/null

  echo "Unpacking archive..."
  local asset_filename=$(find $download_dir -regex ".*${asset_regex}" 2> /dev/null | awk '{ print length(), $0 | "sort -n" }' | cut -d' ' -f2 | head -1)
  unpack_archive "$asset_filename" "$unarchive_opts" | pr -t -o 4

  echo "Installing..."
  if [[ -z "$asset_files" || "$asset_files" == "null" ]]; then
    install_binary $package_name $package_name | pr -t -o 4
  else
    for file_pair in $asset_files; do
      local source="$(render_value $(echo $file_pair | cut -d, -f1))"
      local dest="$(render_value $(echo $file_pair | cut -d, -f2))"
      install_binary "$source" "$dest" "$upx_pack" | pr -t -o 4
    done
  fi

  popd > /dev/null
  rm -rf $download_dir
}

main() {
  local release_yaml="$1"

  # process each github-release
  for item in $(yq -e '.[].name' $release_yaml); do
    echo "$item: installing..."
    install_release "$item" "$release_yaml" | pr -t -o 4
    echo "$item: done"
    echo
  done
}

main $RELEASES_FILE
