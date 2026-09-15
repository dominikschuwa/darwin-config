# MLX with the Metal GPU backend, repackaged from Apple's official PyPI
# wheels instead of building from source.
#
# Why not the nixpkgs `mlx`? Its derivation builds with
# `MLX_BUILD_METAL=false` because Apple's `metal` shader compiler is
# closed-source and unavailable in the Nix build sandbox, so all inference
# runs on CPU -- unusably slow. Apple's PyPI wheels ship the Metal kernels
# *pre-compiled*, so repacking them gives us GPU support with no sandbox
# escape (approach borrowed from
# https://aldur.blog/micros/2025/11/04/mlx-with-metal-support-through-nix/).
#
# Upstream splits the distribution in two:
#   - `mlx`        cpXY wheel with the Python code + nanobind `core` module
#   - `mlx_metal`  py3 wheel carrying `mlx/lib/libmlx.dylib` (Metal kernels
#                  baked in as metallib) that `core` links via @rpath
#
# pip would install both into the same `site-packages/mlx/` directory so
# core's `@loader_path/lib` rpath resolves. In Nix they'd be separate store
# paths merged by a symlink farm, which dyld does not reliably resolve
# through -- so we copy the lib directory into this package's output and
# additionally pin an absolute rpath on every extension module.
#
# WARN: pinned to a specific Python ABI (cp313) and macOS SDK floor
# (macosx_14_0, i.e. runs on macOS >= 14). Bumping `version`, nixpkgs'
# default python3, or supporting older macOS means updating the wheel
# coordinates + hashes below (grab them from
# https://pypi.org/pypi/mlx/json and https://pypi.org/pypi/mlx-metal/json).
{
  lib,
  stdenv,
  buildPythonPackage,
  fetchPypi,
  python,
  pythonAtLeast,
  pythonOlder,
}:

let
  version = "0.31.2";
  format = "wheel";
  platform = "macosx_14_0_arm64";

  mlx-metal = buildPythonPackage {
    pname = "mlx_metal";
    inherit version format;

    src = fetchPypi {
      pname = "mlx_metal";
      inherit version format platform;
      python = "py3";
      dist = "py3";
      hash = "sha256-slOFvO4Y/BlAkiVbi1O5o9hInrZQ5ZFg8bV6rdB6otw=";
    };

    # Pre-built binaries: stripping or fixup would invalidate signatures.
    dontStrip = true;
    doCheck = false;
  };
in
buildPythonPackage rec {
  pname = "mlx";
  inherit version format;

  # The wheel is ABI-tagged; refuse to build against the wrong Python so a
  # nixpkgs python bump fails loudly here instead of at import time.
  disabled = pythonOlder "3.13" || pythonAtLeast "3.14";

  src = fetchPypi {
    inherit
      pname
      version
      format
      platform
      ;
    python = "cp313";
    dist = "cp313";
    abi = "cp313";
    hash = "sha256-Gz+w3alVsNVSzle91vQrMwmrIbBn5AWH1oSEQ9MH6R8=";
  };

  # The wheel metadata declares `mlx-metal` as a runtime dep; we vendor its
  # lib directory below instead of exposing it as a separate package (two
  # packages owning `site-packages/mlx/` would collide in python envs).
  pythonRemoveDeps = [ "mlx-metal" ];

  # Vendor libmlx.dylib (+ metallib) next to the bindings so both
  # `@loader_path/lib` and the absolute rpath below resolve.
  postInstall = ''
    cp -r ${mlx-metal}/${python.sitePackages}/mlx/lib \
      $out/${python.sitePackages}/mlx/
  '';

  postFixup = ''
    libdir=$out/${python.sitePackages}/mlx
    for so in "$libdir"/*.so; do
      [ -f "$so" ] || continue
      install_name_tool -add_rpath "$libdir/lib" "$so"
    done
  '';

  dontStrip = true;
  doCheck = false;

  # Importing mlx.core dlopens libmlx.dylib, proving the rpath wiring works.
  # (Metal *device* creation is lazy, so this also passes in the sandbox.)
  pythonImportsCheck = [ "mlx.core" ];

  meta = {
    description = "Array framework for Apple silicon (official wheels, Metal GPU backend included)";
    homepage = "https://github.com/ml-explore/mlx";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    broken = !stdenv.hostPlatform.isDarwin || !stdenv.hostPlatform.isAarch64;
  };
}
