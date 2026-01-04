# Example flake.nix showing how to use ip-allocator-webserver in your NixOS config
#
# This is a complete example of a NixOS flake that imports and uses the
# ip-allocator-webserver module with persistent Redis.

{
  description = "My NixOS configuration with IP Allocator Webserver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Import the ip-allocator-webserver flake
    ip-allocator-webserver = {
      url = "github:r33drichards/ip-allocator-webserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ip-allocator-webserver, ... }: {
    nixosConfigurations.myserver = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import the NixOS module
        ip-allocator-webserver.nixosModules.default

        # Apply the overlay to get the package
        {
          nixpkgs.overlays = [ ip-allocator-webserver.overlays.default ];
        }

        # Your configuration
        ({ config, pkgs, ... }: {
          # Enable the IP allocator service
          services.ip-allocator-webserver = {
            enable = true;
            package = pkgs.ip-allocator-webserver;
            port = 8000;
            redisUrl = "redis://127.0.0.1:6379/";
            openFirewall = true;

            # Optional: Configure webhook subscribers
            subscribers.borrow.subscribers.myWebhook = {
              post = "http://localhost:9000/on-borrow";
              mustSucceed = false;
              async = false;
            };
          };

          # Redis with persistence for durable storage
          services.redis.servers."ip-allocator" = {
            enable = true;
            port = 6379;
            bind = "127.0.0.1";

            settings = {
              # RDB snapshots
              save = "900 1 300 10 60 10000";

              # AOF persistence
              appendonly = "yes";
              appendfsync = "everysec";

              # Memory limits
              maxmemory = "256mb";
              maxmemory-policy = "noeviction";
            };
          };

          # Ensure proper service ordering
          systemd.services.ip-allocator-webserver = {
            after = [ "redis-ip-allocator.service" ];
            wants = [ "redis-ip-allocator.service" ];
          };

          # ... rest of your NixOS configuration
        })
      ];
    };
  };
}
