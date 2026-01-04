{
  description = "IP Allocator Webserver with Rust SDK and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    let
      # System-independent outputs
      nixosModuleOutputs = {
        # NixOS module for the IP Allocator Webserver
        nixosModules.default = import ./nix/module.nix;
        nixosModules.ip-allocator-webserver = import ./nix/module.nix;

        # Overlay to add the package to nixpkgs
        overlays.default = final: prev: {
          ip-allocator-webserver = self.packages.${final.system}.default;
        };
      };

      # Per-system outputs
      perSystemOutputs = flake-utils.lib.eachDefaultSystem (system:
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs {
            inherit system overlays;
          };

          # Use the specific Rust toolchain required by Rocket
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
          };

          # Build inputs for the Rust project
          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
          ];

          buildInputs = with pkgs; [
            openssl
            redis
          ];

          # Package the Rust webserver application
          rustPackage = pkgs.rustPlatform.buildRustPackage {
            pname = "ip-allocator-webserver";
            version = "0.2.0";

            src = ./.;

            cargoLock = {
              lockFile = ./Cargo.lock;
            };

            nativeBuildInputs = nativeBuildInputs;
            buildInputs = buildInputs;

            meta = with pkgs.lib; {
              description = "IP Allocator webserver with Redis backing store";
              homepage = "https://github.com/r33drichards/ip-allocator-webserver";
              license = licenses.mit;
              maintainers = [];
              mainProgram = "ip-allocator-webserver";
            };
          };

          # Script to generate and build Rust SDK
          generateRustSdkScript = pkgs.writeShellScriptBin "generate-rust-sdk" ''
            set -e

            SDK_DIR="ip-allocator-client"
            CARGO_TOML="$SDK_DIR/Cargo.toml"

            if [ ! -f "$CARGO_TOML" ]; then
              echo "Error: $CARGO_TOML not found"
              exit 1
            fi

            # Extract version and metadata from SDK Cargo.toml
            SDK_VERSION=$(${pkgs.gnugrep}/bin/grep -E '^version = ' "$CARGO_TOML" | head -1 | ${pkgs.gnused}/bin/sed 's/version = "\(.*\)"/\1/')
            SDK_NAME=$(${pkgs.gnugrep}/bin/grep -E '^name = ' "$CARGO_TOML" | head -1 | ${pkgs.gnused}/bin/sed 's/name = "\(.*\)"/\1/')

            echo "Package: $SDK_NAME"
            echo "Version: $SDK_VERSION"

            echo "Generating OpenAPI specification..."
            ${rustPackage}/bin/ip-allocator-webserver --print-openapi > "$SDK_DIR/openapi.json"

            echo "OpenAPI spec generated successfully!"
            echo ""
            echo "OpenAPI spec: $SDK_DIR/openapi.json"
            echo ""
            echo "Note: SDK code will be generated during cargo build via build.rs"
          '';

        in
        {
          # Development shell
          devShells.default = pkgs.mkShell {
            inherit buildInputs nativeBuildInputs;

            packages = with pkgs; [
              # Development tools
              cargo-watch
              cargo-edit

              # Docker tools
              docker
              docker-compose

              # Testing and debugging
              curl
              jq

              # Redis CLI for debugging
              redis
            ];

            shellHook = ''
              echo "IP Allocator Webserver Development Environment"
              echo "==============================================="
              echo "Rust version: $(rustc --version)"
              echo "Cargo version: $(cargo --version)"
              echo ""
              echo "Available commands:"
              echo "  cargo build          - Build the project"
              echo "  cargo run            - Run the webserver"
              echo "  cargo test           - Run unit tests"
              echo "  nix run .#generateRustSdk - Generate Rust SDK"
              echo ""
              echo "OpenAPI Documentation:"
              echo "  Swagger UI: http://localhost:8000/swagger-ui/"
              echo "  RapiDoc:    http://localhost:8000/rapidoc/"
              echo ""
            '';

            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
            REDIS_URL = "redis://127.0.0.1:6379/";
          };

          # Package the Rust application
          packages.default = rustPackage;
          packages.ip-allocator-webserver = rustPackage;

          # Docker image
          packages.docker = pkgs.dockerTools.buildLayeredImage {
            name = "ip-allocator-webserver";
            tag = "latest";
            contents = [ self.packages.${system}.default ];
            config = {
              Cmd = [ "${self.packages.${system}.default}/bin/ip-allocator-webserver" ];
              ExposedPorts = {
                "8000/tcp" = {};
              };
            };
          };

          # Apps
          apps.generateRustSdk = {
            type = "app";
            program = "${generateRustSdkScript}/bin/generate-rust-sdk";
          };
        } // (if pkgs.stdenv.isLinux then {
          # NixOS VM tests (Linux only)
          checks.vm-test = import ./nix/tests/vm-test.nix {
            inherit pkgs self;
          };
          checks.subscriber-tutorial-test = import ./nix/tests/subscriber-tutorial-test.nix {
            inherit pkgs self;
          };
        } else {})
      );
    in
    # Merge system-independent and per-system outputs
    nixosModuleOutputs // perSystemOutputs;
}
