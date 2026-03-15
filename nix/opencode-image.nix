{ pkgs, n2c, devShellPackages, opencodeAi, nixPackage }:
let
  n2cCompatPkgs = pkgs // {
    go = pkgs.go_1_24;
    buildGoModule = pkgs.buildGo124Module;
  };

  # Import the flake input source path directly to avoid import-from-derivation.
  n2cLib = import n2c.outPath { pkgs = n2cCompatPkgs; };

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
    fd
    findutils
    gawk
    git
    gnugrep
    gnused
    gnutar
    gzip
    less
    nixPackage
    openssh
    procps
    ripgrep
    which
    xz
    cacert
    glibc
    nodejs
  ];

  imageEnv = pkgs.buildEnv {
    name = "opencode-container-image-root";
    paths = devShellPackages ++ baseImagePackages ++ [ opencodeAi ];
    pathsToLink = [
      "/bin"
      "/lib"
      "/etc/ssl/certs"
    ];
  };

  imageClosure = pkgs.closureInfo {
    rootPaths = [ imageEnv ];
  };

  imageRoot = pkgs.runCommand "opencode-container-image-rootfs" { } ''
    mkdir -p $out
    cp -a ${imageEnv}/. $out/
    chmod -R u+w $out

    mkdir -p $out/nix/store
    while IFS= read -r store_path; do
      cp -a "$store_path" "$out/nix/store/"
    done < ${imageClosure}/store-paths

    mkdir -p \
      $out/tmp/opencode-container-home \
      $out/tmp/opencode-container-config \
      $out/tmp/opencode-container-cache
    chmod 0777 \
      $out/tmp/opencode-container-home \
      $out/tmp/opencode-container-config \
      $out/tmp/opencode-container-cache

    mkdir -p $out/etc/nix
    cat > $out/etc/nix/nix.conf <<'EOF'
    experimental-features = nix-command flakes
    allow-import-from-derivation = true
    build-users-group =
    sandbox = false
    EOF

    mkdir -p $out/lib64 $out/lib/${libcDir}
    ln -sfn ${pkgs.glibc}/lib/${loaderName} $out/lib64/${loaderName}
    ln -sfn ${pkgs.glibc}/lib/libc.so.6 $out/lib/libc.so.6
    ln -sfn ${pkgs.glibc}/lib/libpthread.so.0 $out/lib/libpthread.so.0
    ln -sfn ${pkgs.glibc}/lib/libdl.so.2 $out/lib/libdl.so.2
    ln -sfn ${pkgs.glibc}/lib/libm.so.6 $out/lib/libm.so.6
    ln -sfn ../libc.so.6 $out/lib/${libcDir}/libc.so.6
    ln -sfn ../libpthread.so.0 $out/lib/${libcDir}/libpthread.so.0
    ln -sfn ../libdl.so.2 $out/lib/${libcDir}/libdl.so.2
    ln -sfn ../libm.so.6 $out/lib/${libcDir}/libm.so.6
  '';

  image = n2cLib.nix2container.buildImage {
    name = "opencode-container";
    tag = "latest";
    copyToRoot = imageRoot;
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
  };
in
image // {
  rootfs = imageRoot;
}
