#!/usr/bin/env bash
set -euo pipefail

KERNEL_REPO="https://github.com/neokoni/android_kernel_xiaomi_nabu.git"
KERNEL_COMMIT="79ac1a92d69a248e76a032f7ab37ab8acee8f17c"
KSU_REPO="https://github.com/rsuntk/KernelSU.git"
KSU_COMMIT="648e5988cf421172769f80ce07f86331b548c053"
REKERNEL_REPO="https://github.com/myflavor/ReKernel-X.git"
REKERNEL_COMMIT="6f9f96dfc725ce12410c8258464a6edd7ec8ca36"
CLANG_TAG="android-16.0.0_r4"
CLANG_REVISION="clang-r563880c"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-/tmp/nk}"
WORK_DIR="${BUILD_ROOT}/work"
CACHE_DIR="${ROOT_DIR}/work"
KERNEL_DIR="${WORK_DIR}/kernel"
KSU_DIR="${KERNEL_DIR}/KernelSU"
REKERNEL_DIR="${WORK_DIR}/ReKernel-X"
OUT_DIR="${BUILD_ROOT}/out"
ARTIFACT_DIR="${ROOT_DIR}/out"
TOOLCHAIN_DIR="${CACHE_DIR}/${CLANG_REVISION}"
TOOLCHAIN_ARCHIVE="${CACHE_DIR}/${CLANG_REVISION}.tar.gz"

mkdir -p "${WORK_DIR}" "${CACHE_DIR}" "${OUT_DIR}" "${ARTIFACT_DIR}"

if [[ ! -d "${KERNEL_DIR}/.git" ]]; then
  git clone --filter=blob:none --no-checkout "${KERNEL_REPO}" "${KERNEL_DIR}"
fi
git -C "${KERNEL_DIR}" fetch --depth 1 origin "${KERNEL_COMMIT}"
git -C "${KERNEL_DIR}" checkout --detach --force "${KERNEL_COMMIT}"
git -C "${KERNEL_DIR}" clean -ffdqx

if [[ ! -d "${KSU_DIR}/.git" ]]; then
  git clone --filter=blob:none --no-checkout "${KSU_REPO}" "${KSU_DIR}"
fi
git -C "${KSU_DIR}" fetch --depth 1 origin "${KSU_COMMIT}"
git -C "${KSU_DIR}" checkout --detach --force "${KSU_COMMIT}"
git -C "${KSU_DIR}" clean -ffdqx

if [[ ! -d "${REKERNEL_DIR}/.git" ]]; then
  git clone --filter=blob:none --no-checkout "${REKERNEL_REPO}" "${REKERNEL_DIR}"
fi
git -C "${REKERNEL_DIR}" fetch --depth 1 origin "${REKERNEL_COMMIT}"
git -C "${REKERNEL_DIR}" checkout --detach --force "${REKERNEL_COMMIT}"
git -C "${REKERNEL_DIR}" clean -ffdqx

(
  cd "${KERNEL_DIR}"
  bash "${REKERNEL_DIR}/Integrate/patches.sh"

  grep -q 'CONFIG_REKERNEL=y' arch/arm64/configs/defconfig
  grep -q 'rekernel_binder_transaction' drivers/android/binder.c
  grep -q 'rekernel_report(SIGNAL' kernel/signal.c
)

if [[ ! -x "${TOOLCHAIN_DIR}/bin/clang" ]]; then
  if [[ ! -s "${TOOLCHAIN_ARCHIVE}" ]]; then
    curl --fail --location --retry 3 \
      "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/${CLANG_TAG}/${CLANG_REVISION}.tar.gz" \
      --output "${TOOLCHAIN_ARCHIVE}"
  fi
  rm -rf "${TOOLCHAIN_DIR}"
  mkdir -p "${TOOLCHAIN_DIR}"
  tar -xzf "${TOOLCHAIN_ARCHIVE}" -C "${TOOLCHAIN_DIR}"
fi

if [[ "${1:-}" == "--prepare-toolchain" ]]; then
  exit 0
fi

CCACHE_BIN_DIR="${CACHE_DIR}/ccache-bin"
mkdir -p "${CCACHE_BIN_DIR}"
ln -sf "$(command -v ccache)" "${CCACHE_BIN_DIR}/clang"
export PATH="${CCACHE_BIN_DIR}:${TOOLCHAIN_DIR}/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER=piter
export KBUILD_BUILD_HOST=github-actions

MAKE_ARGS=(
  -C "${KERNEL_DIR}"
  O="${OUT_DIR}"
  ARCH=arm64
  CC=clang
  HOSTCC=clang
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  STRIP=llvm-strip
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  KCFLAGS=-Wno-error=gnu-variable-sized-type-not-at-end
)

cp "${ROOT_DIR}/configs/nabu-running.config" "${OUT_DIR}/.config"

"${KERNEL_DIR}/scripts/config" --file "${OUT_DIR}/.config" \
  --enable KSU \
  --enable KSU_MANUAL_HOOK \
  --enable KSU_FEATURE_ADBROOT \
  --disable KSU_DEBUG \
  --enable USER_NS \
  --enable PID_NS \
  --enable IPC_NS \
  --enable UTS_NS \
  --enable DEVTMPFS \
  --enable DEVTMPFS_MOUNT \
  --enable REKERNEL \
  --disable REKERNEL_NETWORK

make "${MAKE_ARGS[@]}" olddefconfig

grep -q '^CONFIG_KSU=y$' "${OUT_DIR}/.config"
grep -q '^CONFIG_USER_NS=y$' "${OUT_DIR}/.config"
grep -q '^CONFIG_REKERNEL=y$' "${OUT_DIR}/.config"

make -j"$(nproc)" "${MAKE_ARGS[@]}" Image

test -s "${OUT_DIR}/arch/arm64/boot/Image"

{
  echo "kernel=${KERNEL_COMMIT}"
  echo "kernelsu=${KSU_COMMIT}"
  echo "rekernel_x=${REKERNEL_COMMIT}"
  echo "compiler=$(clang --version | head -n 1)"
  echo "image_sha256=$(sha256sum "${OUT_DIR}/arch/arm64/boot/Image" | awk '{print $1}')"
} > "${OUT_DIR}/build-info.txt"

cp "${OUT_DIR}/arch/arm64/boot/Image" "${ARTIFACT_DIR}/Image"
cp "${OUT_DIR}/.config" "${ARTIFACT_DIR}/.config"
cp "${OUT_DIR}/build-info.txt" "${ARTIFACT_DIR}/build-info.txt"
