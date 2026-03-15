{ pkgs, devShellPackages, opencodeAi }:
let
  loaderName =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "ld-linux-x86-64.so.2"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "ld-linux-aarch64.so.1"
    else
      throw "Unsupported Linux architecture for opencode image";

  libcDir =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64-linux-gnu"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64-linux-gnu"
    else
      throw "Unsupported Linux architecture for opencode image";

  baseImagePackages = with pkgs; [
    bashInteractive
    coreutils
    curl
    findutils
    gawk
    gnugrep
    gnused
    gnutar
    gzip
    less
    nix
    procps
    which
    xz
    cacert
    glibc
    nodejs
  ];

  imageRoot = pkgs.buildEnv {
    name = "opencode-container-image-root";
    paths = devShellPackages ++ baseImagePackages ++ [ opencodeAi ];
    pathsToLink = [
      "/bin"
      "/lib"
      "/etc/ssl/certs"
    ];
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "opencode-container";
  tag = "latest";
  contents = [ imageRoot ];
  extraCommands = ''
    mkdir -p tmp/opencode-container-home tmp/opencode-container-config tmp/opencode-container-cache
    chmod 0777 tmp/opencode-container-home tmp/opencode-container-config tmp/opencode-container-cache
    mkdir -p lib64 lib/${libcDir}
    ln -sfn ${pkgs.glibc}/lib/${loaderName} lib64/${loaderName}
    ln -sfn ${pkgs.glibc}/lib/libc.so.6 lib/libc.so.6
    ln -sfn ${pkgs.glibc}/lib/libpthread.so.0 lib/libpthread.so.0
    ln -sfn ${pkgs.glibc}/lib/libdl.so.2 lib/libdl.so.2
    ln -sfn ${pkgs.glibc}/lib/libm.so.6 lib/libm.so.6
    ln -sfn ../libc.so.6 lib/${libcDir}/libc.so.6
    ln -sfn ../libpthread.so.0 lib/${libcDir}/libpthread.so.0
    ln -sfn ../libdl.so.2 lib/${libcDir}/libdl.so.2
    ln -sfn ../libm.so.6 lib/${libcDir}/libm.so.6
  '';
  config = {
    Cmd = [ "/bin/bash" ];
    Env = [
      "PATH=/bin"
      "HOME=/tmp/opencode-container-home"
      "XDG_CONFIG_HOME=/tmp/opencode-container-config"
      "XDG_CACHE_HOME=/tmp/opencode-container-cache"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
  };
}
