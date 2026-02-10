#!/bin/sh
set -eu

if command -v mise; then
    echo "mise already installed at $(command -v mise)"
    exit 0
fi

#region logging setup
if [ "${MISE_DEBUG-}" = "true" ] || [ "${MISE_DEBUG-}" = "1" ]; then
  debug() {
    echo "$@" >&2
  }
else
  debug() {
    :
  }
fi

if [ "${MISE_QUIET-}" = "1" ] || [ "${MISE_QUIET-}" = "true" ]; then
  info() {
    :
  }
else
  info() {
    echo "$@" >&2
  }
fi

error() {
  echo "$@" >&2
  exit 1
}
#endregion

#region environment setup
get_os() {
  os="$(uname -s)"
  if [ "$os" = Darwin ]; then
    echo "macos"
  elif [ "$os" = Linux ]; then
    echo "linux"
  else
    error "unsupported OS: $os"
  fi
}

get_arch() {
  musl=""
  if type ldd >/dev/null 2>/dev/null; then
    libc=$(ldd /bin/ls | grep 'musl' | head -1 | cut -d ' ' -f1)
    if [ -n "$libc" ]; then
      musl="-musl"
    fi
  fi
  arch="$(uname -m)"
  if [ "$arch" = x86_64 ]; then
    echo "x64$musl"
  elif [ "$arch" = aarch64 ] || [ "$arch" = arm64 ]; then
    echo "arm64$musl"
  elif [ "$arch" = armv7l ]; then
    echo "armv7$musl"
  else
    error "unsupported architecture: $arch"
  fi
}

get_ext() {
  if [ -n "${MISE_INSTALL_EXT:-}" ]; then
    echo "$MISE_INSTALL_EXT"
  elif [ -n "${MISE_VERSION:-}" ] && echo "$MISE_VERSION" | grep -q '^v2024'; then
    # 2024 versions don't have zstd tarballs
    echo "tar.gz"
  elif tar_supports_zstd; then
    echo "tar.zst"
  elif command -v zstd >/dev/null 2>&1; then
    echo "tar.zst"
  else
    echo "tar.gz"
  fi
}

tar_supports_zstd() {
  # tar is bsdtar or version is >= 1.31
  if tar --version | grep -q 'bsdtar' && command -v zstd >/dev/null 2>&1; then
    true
  elif tar --version | grep -q '1\.(3[1-9]|[4-9][0-9]'; then
    true
  else
    false
  fi
}

shasum_bin() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  else
    error "mise install requires shasum or sha256sum but neither is installed. Aborting."
  fi
}

get_checksum() {
  version=$1
  os="$(get_os)"
  arch="$(get_arch)"
  ext="$(get_ext)"
  url="https://github.com/jdx/mise/releases/download/v${version}/SHASUMS256.txt"

  # For current version use static checksum otherwise
  # use checksum from releases
  if [ "$version" = "v2026.2.2" ]; then
    checksum_linux_x86_64="7d1ffcceb32f861d9d0e00b7ccabe9ee962d6ca51daa7f66715c46b9856169d8  ./mise-v2026.2.2-linux-x64.tar.gz"
    checksum_linux_x86_64_musl="e92eeadcc9816f8162121c0c602b4e17a844fcc40d2be0e4be4aaf4465c5a859  ./mise-v2026.2.2-linux-x64-musl.tar.gz"
    checksum_linux_arm64="86576902e7cb0fe860d192961c6fecc756e585c16420b0c00c9485bc64f8f86d  ./mise-v2026.2.2-linux-arm64.tar.gz"
    checksum_linux_arm64_musl="d1b4af5eeac4a7cd84fd24f161777c3c0915d615d9b589695adfef358e68b073  ./mise-v2026.2.2-linux-arm64-musl.tar.gz"
    checksum_linux_armv7="122f811e4118b638af448c732c4cd5b67df89a103fd173efcb350ff18d348c4b  ./mise-v2026.2.2-linux-armv7.tar.gz"
    checksum_linux_armv7_musl="b22f1896521f1e7f213bfcf0b172737fc8c3e6863034f51c285883b638484d6f  ./mise-v2026.2.2-linux-armv7-musl.tar.gz"
    checksum_macos_x86_64="427877316ac15703722bf40265d275a8234bec49400be249191057fa2bff98bc  ./mise-v2026.2.2-macos-x64.tar.gz"
    checksum_macos_arm64="ba27908d3c4430b928542e654d21e275f4aadc7d804e41f6bc61f7967c8469d5  ./mise-v2026.2.2-macos-arm64.tar.gz"
    checksum_linux_x86_64_zstd="6f2c7d8b42fc12d9356422f5b54639f4e34648d537a62e84ae71c751b7a9dd0b  ./mise-v2026.2.2-linux-x64.tar.zst"
    checksum_linux_x86_64_musl_zstd="0dc09d7dff5a2874d7b0859fd5e544ca5d35e1dac40659814f1f8b32a92acdc6  ./mise-v2026.2.2-linux-x64-musl.tar.zst"
    checksum_linux_arm64_zstd="857b0740eb35f90e3bcb1da3a9a5b84b857f9738720747ac4f84a6ece03d1a0e  ./mise-v2026.2.2-linux-arm64.tar.zst"
    checksum_linux_arm64_musl_zstd="20e6ae3785d9f857ffd18d13800106c76841b22a082db441b511589a72311122  ./mise-v2026.2.2-linux-arm64-musl.tar.zst"
    checksum_linux_armv7_zstd="54b85360ddafbfeff76c3f7e8db6d20b55812907295e38420921ca8d2b77e8f9  ./mise-v2026.2.2-linux-armv7.tar.zst"
    checksum_linux_armv7_musl_zstd="64c50b95f736da764db64ce663f79b58ec8d089f69cc1b130f086724f3736ebf  ./mise-v2026.2.2-linux-armv7-musl.tar.zst"
    checksum_macos_x86_64_zstd="ce88730c4f80c5a74bd98e8fbe248be8cb42f1d93eb9e5a1722fb90e87165c9e  ./mise-v2026.2.2-macos-x64.tar.zst"
    checksum_macos_arm64_zstd="acff4722efa3ab7d620e58165ff6262fa131d0912e36aeb242fc1fd0ded5bfee  ./mise-v2026.2.2-macos-arm64.tar.zst"

    # TODO: refactor this, it's a bit messy
    if [ "$(get_ext)" = "tar.zst" ]; then
      if [ "$os" = "linux" ]; then
        if [ "$arch" = "x64" ]; then
          echo "$checksum_linux_x86_64_zstd"
        elif [ "$arch" = "x64-musl" ]; then
          echo "$checksum_linux_x86_64_musl_zstd"
        elif [ "$arch" = "arm64" ]; then
          echo "$checksum_linux_arm64_zstd"
        elif [ "$arch" = "arm64-musl" ]; then
          echo "$checksum_linux_arm64_musl_zstd"
        elif [ "$arch" = "armv7" ]; then
          echo "$checksum_linux_armv7_zstd"
        elif [ "$arch" = "armv7-musl" ]; then
          echo "$checksum_linux_armv7_musl_zstd"
        else
          warn "no checksum for $os-$arch"
        fi
      elif [ "$os" = "macos" ]; then
        if [ "$arch" = "x64" ]; then
          echo "$checksum_macos_x86_64_zstd"
        elif [ "$arch" = "arm64" ]; then
          echo "$checksum_macos_arm64_zstd"
        else
          warn "no checksum for $os-$arch"
        fi
      else
        warn "no checksum for $os-$arch"
      fi
    else
      if [ "$os" = "linux" ]; then
        if [ "$arch" = "x64" ]; then
          echo "$checksum_linux_x86_64"
        elif [ "$arch" = "x64-musl" ]; then
          echo "$checksum_linux_x86_64_musl"
        elif [ "$arch" = "arm64" ]; then
          echo "$checksum_linux_arm64"
        elif [ "$arch" = "arm64-musl" ]; then
          echo "$checksum_linux_arm64_musl"
        elif [ "$arch" = "armv7" ]; then
          echo "$checksum_linux_armv7"
        elif [ "$arch" = "armv7-musl" ]; then
          echo "$checksum_linux_armv7_musl"
        else
          warn "no checksum for $os-$arch"
        fi
      elif [ "$os" = "macos" ]; then
        if [ "$arch" = "x64" ]; then
          echo "$checksum_macos_x86_64"
        elif [ "$arch" = "arm64" ]; then
          echo "$checksum_macos_arm64"
        else
          warn "no checksum for $os-$arch"
        fi
      else
        warn "no checksum for $os-$arch"
      fi
    fi
  else
    if command -v curl >/dev/null 2>&1; then
      debug ">" curl -fsSL "$url"
      checksums="$(curl --compressed -fsSL "$url")"
    else
      if command -v wget >/dev/null 2>&1; then
        debug ">" wget -qO - "$url"
        stderr=$(mktemp)
        checksums="$(wget -qO - "$url")"
      else
        error "mise standalone install specific version requires curl or wget but neither is installed. Aborting."
      fi
    fi
    # TODO: verify with minisign or gpg if available

    checksum="$(echo "$checksums" | grep "$os-$arch.$ext")"
    if ! echo "$checksum" | grep -Eq "^([0-9a-f]{32}|[0-9a-f]{64})"; then
      warn "no checksum for mise $version and $os-$arch"
    else
      echo "$checksum"
    fi
  fi
}

#endregion

download_file() {
  url="$1"
  filename="$(basename "$url")"
  cache_dir="$(mktemp -d)"
  file="$cache_dir/$filename"

  info "mise: installing mise..."

  if command -v curl >/dev/null 2>&1; then
    debug ">" curl -#fLo "$file" "$url"
    curl -#fLo "$file" "$url"
  else
    if command -v wget >/dev/null 2>&1; then
      debug ">" wget -qO "$file" "$url"
      stderr=$(mktemp)
      wget -O "$file" "$url" >"$stderr" 2>&1 || error "wget failed: $(cat "$stderr")"
    else
      error "mise standalone install requires curl or wget but neither is installed. Aborting."
    fi
  fi

  echo "$file"
}

install_mise() {
  version="${MISE_VERSION:-v2026.2.2}"
  version="${version#v}"
  os="$(get_os)"
  arch="$(get_arch)"
  ext="$(get_ext)"
  install_path="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"

  if [ -x "$install_path" ]; then
    debug "mise-setup: already installed"
    exit 0
  fi

  install_dir="$(dirname "$install_path")"
  tarball_url="https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-${os}-${arch}.${ext}"

  cache_file=$(download_file "$tarball_url")
  debug "mise-setup: tarball=$cache_file"

  debug "validating checksum"
  cd "$(dirname "$cache_file")" && get_checksum "$version" | "$(shasum_bin)" -c >/dev/null

  # extract tarball
  mkdir -p "$install_dir"
  rm -rf "$install_path"
  cd "$(mktemp -d)"
  if [ "$(get_ext)" = "tar.zst" ] && ! tar_supports_zstd; then
    zstd -d -c "$cache_file" | tar -xf -
  else
    tar -xf "$cache_file"
  fi
  mv mise/bin/mise "$install_path"
  info "mise: installed successfully to $install_path"
}

after_finish_help() {
  case "${SHELL:-}" in
  */zsh)
    info "mise: run the following to activate mise in your shell:"
    info "echo \"eval \\\"\\\$($install_path activate zsh)\\\"\" >> \"${ZDOTDIR-$HOME}/.zshrc\""
    info ""
    info "mise: run \`mise doctor\` to verify this is setup correctly"
    ;;
  */bash)
    info "mise: run the following to activate mise in your shell:"
    info "echo \"eval \\\"\\\$($install_path activate bash)\\\"\" >> ~/.bashrc"
    info ""
    info "mise: run \`mise doctor\` to verify this is setup correctly"
    ;;
  */fish)
    info "mise: run the following to activate mise in your shell:"
    info "echo \"$install_path activate fish | source\" >> ~/.config/fish/config.fish"
    info ""
    info "mise: run \`mise doctor\` to verify this is setup correctly"
    ;;
  *)
    info "mise: run \`$install_path --help\` to get started"
    ;;
  esac
}

install_mise
if [ "${MISE_INSTALL_HELP-}" != 0 ]; then
  after_finish_help
fi
