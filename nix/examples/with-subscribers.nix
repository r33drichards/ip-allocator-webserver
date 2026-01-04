# Advanced example: ip-allocator-webserver with webhook subscribers
#
# This example shows how to configure webhook subscribers for
# borrow, return, and submit events.

{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;

    # Custom port and address
    port = 8080;
    address = "0.0.0.0";

    # Custom Redis URL
    redisUrl = "redis://redis.example.com:6379/0";

    # Open firewall for external access
    openFirewall = true;

    # Configure webhook subscribers
    subscribers = {
      # Notify when an item is borrowed
      borrow.subscribers = {
        # Synchronous webhook - must succeed for borrow to complete
        provisioningService = {
          post = "http://provisioner.internal:8000/on-borrow";
          mustSucceed = true;
          async = false;
        };

        # Async webhook for long-running operations
        asyncProvisioner = {
          post = "http://slow-provisioner.internal:8000/provision";
          mustSucceed = true;
          async = true;
        };

        # Optional notification (fire-and-forget)
        auditLog = {
          post = "http://audit.internal:8000/log";
          mustSucceed = false;
          async = false;
        };
      };

      # Notify when an item is returned
      return.subscribers = {
        cleanupService = {
          post = "http://cleanup.internal:8000/on-return";
          mustSucceed = true;
          async = true;
        };
      };

      # Notify when a new item is submitted
      submit.subscribers = {
        validator = {
          post = "http://validator.internal:8000/validate";
          mustSucceed = true;
          async = false;
        };
      };
    };

    # Extra environment variables
    extraEnvironment = {
      RUST_LOG = "info";
    };
  };

  # Enable Redis
  services.redis.servers."".enable = true;
}
