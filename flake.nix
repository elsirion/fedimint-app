{
  inputs = {
    fedimint.url = "github:m1sterc001guy/fedimint?ref=348d82abf3abed49924e52d0a2dd1761643e8de6";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      self,
      fedimint,
      flake-utils,
      nixpkgs,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidBuildToolsVersion = "35.0.0";
        androidNdkVersion = "27.3.13750724";

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "13.0";
          platformToolsVersion = "35.0.2";
          buildToolsVersions = [
            "34.0.0"
            androidBuildToolsVersion
          ];
          platformVersions = [
            "34"
            "35"
            "36"
          ];
          includeEmulator = false;
          includeNDK = true;
          ndkVersions = [ androidNdkVersion ];
          cmakeVersions = [ "3.22.1" ];
          includeSources = false;
          includeSystemImages = false;
        };

        androidSdk = androidComposition.androidsdk;

        # Import the `devShells` from the fedimint flake
        devShells = fedimint.devShells.${system};

        androidNativeBuildInputs = [
          androidSdk
          pkgs.flutter
          pkgs.gradle
          pkgs.jdk17
          pkgs.just
          pkgs.zlib
          pkgs.cargo-ndk
          pkgs.flutter_rust_bridge_codegen
          pkgs.cargo-expand
        ];

        # Public Android debug keystore used only to keep the debug APK output
        # stable across Nix builds. This is not a release signing key.
        androidDebugKeystoreBase64 = pkgs.writeText "ecashapp-debug.keystore.base64" ''
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
        '';

        androidDebugKeystore = pkgs.runCommand "ecashapp-debug.keystore" { } ''
          ${pkgs.coreutils}/bin/base64 --decode "${androidDebugKeystoreBase64}" > "$out"
        '';

        androidApkBuildInputs = pkgs.lib.flatten ((devShells.cross.nativeBuildInputs or [ ]) ++ androidNativeBuildInputs ++ [
          pkgs.cacert
          pkgs.git
          pkgs.llvmPackages.libclang
        ]);

        androidEnvironment = ''
          export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
          export ANDROID_SDK_ROOT="$ANDROID_HOME"
          export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${androidNdkVersion}"
          export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
          export ANDROID_NDK="$ANDROID_NDK_HOME"
          export JAVA_HOME="${pkgs.jdk17.home}"
          export FLUTTER_ROOT="${pkgs.flutter}"
          export LD_LIBRARY_PATH="${pkgs.zlib}/lib:$LD_LIBRARY_PATH"
          export NIXPKGS_ALLOW_UNFREE=1
          export FLUTTER_SUPPRESS_ANALYTICS=true
          export ROOT="$PWD"
          export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/build-tools/${androidBuildToolsVersion}:$PATH"

          # Tell Gradle to use the Nix-provided JDK and aapt2. The aapt2
          # override avoids downloaded Maven binaries that fail on NixOS.
          _nix_aapt2="$ANDROID_HOME/build-tools/${androidBuildToolsVersion}/aapt2"
          export GRADLE_OPTS="-Dorg.gradle.java.home=$JAVA_HOME -Dorg.gradle.project.android.aapt2FromMavenOverride=$_nix_aapt2 ''${GRADLE_OPTS:-}"
        '';
      in
      {
        packages = {
          default = self.packages.${system}.apk;

          apk = self.packages.${system}.apk-debug;
          aab = self.packages.${system}.aab-release-unsigned;

          apk-debug = pkgs.stdenv.mkDerivation {
            pname = "ecashapp-apk-debug";
            version = "0.9.0-alpha";

            src = self;
            __structuredAttrs = true;

            nativeBuildInputs = androidApkBuildInputs;
            buildInputs = androidApkBuildInputs;

            # Flutter, Gradle, Cargo, and Maven dependencies are still resolved by
            # their upstream tools. Make the APK package a fixed-output derivation
            # so Nix permits those network fetches while pinning the final APK.
            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "sha256-nsfB/sXZoQWf0izglLK8xVqHz1QeY1HbJGY1PIljOgc=";

            # The APK contains Nix store strings from Android/Rust build tools.
            # The output hash pins the artifact content; this prevents Nix from
            # treating those embedded strings as runtime references.
            unsafeDiscardReferences.out = true;

            dontConfigure = true;
            dontFixup = true;

            buildPhase = ''
              runHook preBuild

              export HOME="$TMPDIR/home"
              export PATH="${pkgs.lib.makeBinPath androidApkBuildInputs}:$PATH"
              export GRADLE_USER_HOME="$TMPDIR/gradle"
              export PUB_CACHE="$TMPDIR/pub-cache"
              export CARGO_HOME="$TMPDIR/cargo"
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              export GIT_SSL_CAINFO="$SSL_CERT_FILE"
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              export CARGO_NET_GIT_FETCH_WITH_CLI=true
              mkdir -p "$HOME" "$GRADLE_USER_HOME" "$PUB_CACHE" "$CARGO_HOME"

              export ANDROID_USER_HOME="$HOME/.android"
              mkdir -p "$ANDROID_USER_HOME"
              cp "${androidDebugKeystore}" "$ANDROID_USER_HOME/debug.keystore"
              chmod 600 "$ANDROID_USER_HOME/debug.keystore"

              ${androidEnvironment}

              ${pkgs.bash}/bin/bash scripts/build-android-nix.sh debug

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out"
              cp build/app/outputs/flutter-apk/app-debug.apk "$out/ecashapp-debug.apk"

              runHook postInstall
            '';
          };

          aab-release-unsigned = pkgs.stdenv.mkDerivation {
            pname = "ecashapp-aab-release-unsigned";
            version = "0.9.0-alpha";

            src = self;
            __structuredAttrs = true;

            nativeBuildInputs = androidApkBuildInputs;
            buildInputs = androidApkBuildInputs;

            # Flutter, Gradle, Cargo, and Maven dependencies are still resolved by
            # their upstream tools. Make the AAB package a fixed-output derivation
            # so Nix permits those network fetches while pinning the final bundle.
            outputHashAlgo = "sha256";
            outputHashMode = "recursive";
            outputHash = "sha256-YN97IS9GTOS28cOp5Ovvw77SOwzMveWjUz0i5BJoCMQ=";

            # The AAB contains Nix store strings from Android/Rust build tools.
            # The output hash pins the artifact content; this prevents Nix from
            # treating those embedded strings as runtime references.
            unsafeDiscardReferences.out = true;

            dontConfigure = true;
            dontFixup = true;

            buildPhase = ''
              runHook preBuild

              export HOME="$TMPDIR/home"
              export PATH="${pkgs.lib.makeBinPath androidApkBuildInputs}:$PATH"
              export GRADLE_USER_HOME="$TMPDIR/gradle"
              export PUB_CACHE="$TMPDIR/pub-cache"
              export CARGO_HOME="$TMPDIR/cargo"
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              export GIT_SSL_CAINFO="$SSL_CERT_FILE"
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              export CARGO_NET_GIT_FETCH_WITH_CLI=true
              mkdir -p "$HOME" "$GRADLE_USER_HOME" "$PUB_CACHE" "$CARGO_HOME"

              ${androidEnvironment}

              ${pkgs.bash}/bin/bash scripts/build-android-nix.sh release --aab

              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out"
              cp build/app/outputs/bundle/release/app-release.aab "$out/ecashapp-release-unsigned.aab"

              runHook postInstall
            '';
          };
        };

        devShells = {
          # Start from fedimint's cross shell so Rust/Android cross tooling stays
          # available, then pin the Flutter Android SDK/JDK pieces needed by the
          # app's Gradle project.
          default = devShells.cross.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ androidNativeBuildInputs ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.fdroidserver
              (pkgs.appimage-run.override {
                extraPkgs = pkgs: [
                  pkgs.libepoxy
                  pkgs.gtk3
                ];
              })
            ];

            shellHook = ''
              ${old.shellHook or ""}

              ${androidEnvironment}

              if [ -d android ]; then
                cat > android/local.properties <<EOF
sdk.dir=$ANDROID_HOME
flutter.sdk=$FLUTTER_ROOT
EOF
              fi

              if [ -d .git ]; then
                ln -sf "$PWD/scripts/git-hooks/pre-commit.sh" .git/hooks/pre-commit
              fi
              # Ensure flutter deps are resolved (needed for dart format in pre-commit hook)
              if [ ! -f .dart_tool/package_config.json ]; then
                echo "Running flutter pub get (first-time setup)..."
                flutter pub get > /dev/null 2>&1
              fi
            '';
          });
        };
      }
    );
}
