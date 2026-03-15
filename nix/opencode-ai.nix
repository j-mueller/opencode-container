{ pkgs, system }:
let
  opencodeVersion = "1.2.25";

  opencodeLauncherSrc = pkgs.fetchurl {
    url = "https://registry.npmjs.org/opencode-ai/-/opencode-ai-${opencodeVersion}.tgz";
    hash = "sha512-T1P8eGbc5OUbxzF+j0Of/aqecrgXSB5vH7oJFR/9DmQsBpk+l4mNXSL3yXbXrOyn4v41WS0J4xvJvCfw/Gxgsg==";
  };

  opencodeBinaryMeta = {
    x86_64-linux = {
      packageName = "opencode-linux-x64";
      hash = "sha512-9+H6Rqw8tRYMo6005ZGBqq00cQUW5IAVjLFwusm2/J+Ey7nuIY0K0F0Gq+PejsxeiEyeQ7xMBuzfytcMljZLjA==";
    };
    aarch64-linux = {
      packageName = "opencode-linux-arm64";
      hash = "sha512-IP/53XglHR4OHdFIWq4t5bbVWp9GOL5RYqP85CSCel/bAU2v/Zd3/RLcNOxe+P3NpZxn0/9VFD+iei+G04bOaQ==";
    };
  };

  binaryMeta = opencodeBinaryMeta.${system} or null;
in
if binaryMeta == null then
  null
else
  pkgs.stdenv.mkDerivation {
    pname = "opencode-ai";
    version = opencodeVersion;
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    nativeBuildInputs = with pkgs; [ makeWrapper ];

    inherit opencodeLauncherSrc;
    binarySrc = pkgs.fetchurl {
      url = "https://registry.npmjs.org/${binaryMeta.packageName}/-/${binaryMeta.packageName}-${opencodeVersion}.tgz";
      hash = binaryMeta.hash;
    };

    installPhase = ''
      launcherDir="$TMPDIR/opencode-launcher"
      binaryDir="$TMPDIR/opencode-binary"

      mkdir -p "$launcherDir" "$binaryDir"
      tar -xzf "$opencodeLauncherSrc" -C "$launcherDir"
      tar -xzf "$binarySrc" -C "$binaryDir"

      mkdir -p "$out/bin"
      mkdir -p "$out/lib/node_modules/opencode-ai/bin"
      mkdir -p "$out/lib/node_modules/opencode-ai/node_modules/${binaryMeta.packageName}/bin"

      cp "$launcherDir/package/bin/opencode" "$out/lib/node_modules/opencode-ai/bin/opencode"
      cp "$launcherDir/package/package.json" "$out/lib/node_modules/opencode-ai/package.json"
      cp "$binaryDir/package/bin/opencode" "$out/lib/node_modules/opencode-ai/node_modules/${binaryMeta.packageName}/bin/opencode"
      cp "$binaryDir/package/bin/opencode" "$out/lib/node_modules/opencode-ai/bin/.opencode"
      chmod +x \
        "$out/lib/node_modules/opencode-ai/bin/.opencode" \
        "$out/lib/node_modules/opencode-ai/bin/opencode" \
        "$out/lib/node_modules/opencode-ai/node_modules/${binaryMeta.packageName}/bin/opencode"
      makeWrapper "${pkgs.nodejs}/bin/node" "$out/bin/opencode" \
        --add-flags "$out/lib/node_modules/opencode-ai/bin/opencode"
    '';
  }
