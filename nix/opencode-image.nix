{ pkgs, n2c, devShellPackages, opencodeAi, nixPackage }:
let
  mkOpencodeConfig = import ./opencode-config.nix;
  defaultOpencodeConfigJson = builtins.toJSON (mkOpencodeConfig {
    baseURL = "http://127.0.0.1:11434/v1";
  });

  n2cCompatPkgs = pkgs // {
    go = pkgs.go_1_24;
    buildGoModule = pkgs.buildGo124Module;
  };

  # Import the flake input source path directly to avoid import-from-derivation.
  n2cLib = import n2c.outPath { pkgs = n2cCompatPkgs; };

  skopeoContainersImagePatch = pkgs.fetchpatch2 {
    url = "https://github.com/nlewo/container-libs/commit/21b053ac62f3137de42585611953e923577d0e10.patch";
    sha256 = "sha256-pfwQh7FKWHY/xVAGMSvnjMOmkpMo9NG2HFZqhqZ1VN0=";
    postFetch = ''
      sed -i \
        -e '/^index /d' \
        -e '/^similarity index /d' \
        -e '/^dissimilarity index /d' \
        $out
    '';
  };

  patchedSkopeoN2C = n2cLib.skopeo-nix2container.overrideAttrs (old: {
    preBuild = ''
      patch_file="$(mktemp)"
      cp ${skopeoContainersImagePatch} "$patch_file"
      sed -i 's#go.podman.io/image/v5#github.com/containers/image/v5#g' "$patch_file"
      cat "$patch_file"
      mkdir -p vendor/github.com/nlewo/nix2container/
      cp -r ${n2cLib.nix2container-bin.src}/* vendor/github.com/nlewo/nix2container/
      chmod -R u+w vendor/github.com/nlewo/nix2container/nix
      sed -i 's#go.podman.io/image/v5#github.com/containers/image/v5#g' \
        vendor/github.com/nlewo/nix2container/nix/image.go
      cd vendor/github.com/containers/image/v5
      mkdir nix/
      touch nix/transport.go
      cat "$patch_file" | patch -p2
      cd -

      # Go checks packages in the vendor directory are declared in the modules.txt file.
      awk '
        $0 ~ /^# github.com\/containers\/image\/v5 / { print; in_mod=1; next }
        in_mod && /^## / { print; print "github.com/containers/image/v5/nix"; in_mod=0; next }
        { print }
      ' vendor/modules.txt > vendor/modules.txt.tmp
      mv vendor/modules.txt.tmp vendor/modules.txt

      echo '# github.com/nlewo/nix2container v1.0.0' >> vendor/modules.txt
      echo '## explicit; go 1.13' >> vendor/modules.txt
      echo github.com/nlewo/nix2container/nix >> vendor/modules.txt
      echo github.com/nlewo/nix2container/types >> vendor/modules.txt
      # All packages declared in the modules.txt file must also be required by the go.mod file.
      echo 'require (' >> go.mod
      echo '  github.com/nlewo/nix2container v1.0.0' >> go.mod
      echo ')' >> go.mod
    '';
  });

  writeSkopeoApplication = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = [ pkgs.jq patchedSkopeoN2C ];
    excludeShellChecks = [ "SC2068" ];
  };

  copyToDockerDaemon = image: writeSkopeoApplication "copy-to-docker-daemon" ''
    echo "Copy to Docker daemon image ${image.imageName}:${image.imageTag}"
    skopeo --insecure-policy copy nix:${image} docker-daemon:${image.imageName}:${image.imageTag} "$@"
  '';

  copyToRegistry = image: writeSkopeoApplication "copy-to-registry" ''
    echo "Copy to Docker registry image ${image.imageName}:${image.imageTag}"
    skopeo --insecure-policy copy nix:${image} docker://${image.imageName}:${image.imageTag} "$@"
  '';

  copyToPodman = image: writeSkopeoApplication "copy-to-podman" ''
    echo "Copy to podman image ${image.imageName}:${image.imageTag}"
    skopeo --insecure-policy copy nix:${image} containers-storage:${image.imageName}:${image.imageTag} "$@"
  '';

  copyTo = image: writeSkopeoApplication "copy-to" ''
    echo "Running skopeo --insecure-policy copy nix:${image}" "$@"
    skopeo --insecure-policy copy nix:${image} "$@"
  '';

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

    mkdir -p $out/tmp/opencode-container-config/opencode
    cat > $out/tmp/opencode-container-config/opencode/opencode.json <<'EOF'
    ${defaultOpencodeConfigJson}
    EOF

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

  rawImage = n2cLib.nix2container.buildImage {
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

  image = rawImage // {
    passthru = rawImage.passthru // {
      copyToDockerDaemon = copyToDockerDaemon rawImage;
      copyToRegistry = copyToRegistry rawImage;
      copyToPodman = copyToPodman rawImage;
      copyTo = copyTo rawImage;
    };
    copyToDockerDaemon = copyToDockerDaemon rawImage;
    copyToRegistry = copyToRegistry rawImage;
    copyToPodman = copyToPodman rawImage;
    copyTo = copyTo rawImage;
  };
in
image // {
  rootfs = imageRoot;
}
