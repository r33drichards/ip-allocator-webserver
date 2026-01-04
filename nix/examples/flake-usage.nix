# Example flake.nix showing how to use ip-allocator-webserver in your NixOS config
#
# This is a complete example of a NixOS flake that imports and uses the
# ip-allocator-webserver module.

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
          # Enable the service
          services.ip-allocator-webserver = {
            enable = true;
            package = pkgs.ip-allocator-webserver;
            port = 8000;
            redisUrl = "redis://127.0.0.1:6379/";
            openFirewall = true;

            # Optional: Configure subscribers
            subscribers.borrow.subscribers.myWebhook = {
              post = "http://localhost:9000/on-borrow";
              mustSucceed = false;
              async = false;
            };
          };

          # Enable Redis as the backing store
          services.redis.servers."".enable = true;

          # ... rest of your NixOS configuration
        })
      ];
    };
  };
}
