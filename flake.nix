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
      in
      {
        devShells = {
          # Start from fedimint's cross shell so Rust/Android cross tooling stays
          # available, then pin the Flutter Android SDK/JDK pieces needed by the
          # app's Gradle project.
          default = devShells.cross.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              androidSdk
              pkgs.flutter
              pkgs.gradle
              pkgs.jdk17
              pkgs.just
              pkgs.zlib
              pkgs.cargo-ndk
              pkgs.flutter_rust_bridge_codegen
              pkgs.cargo-expand
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
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
