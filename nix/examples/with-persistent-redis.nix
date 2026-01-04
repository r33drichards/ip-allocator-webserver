# Example: ip-allocator-webserver with persistent Redis
#
# This example shows how to configure Redis with persistence enabled
# so that your IP pool data survives reboots.

{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;
    port = 8000;
    redisUrl = "redis://127.0.0.1:6379/";
    openFirewall = true;

    # Optional: Configure subscribers
    subscribers.borrow.subscribers.logger = {
      post = "http://localhost:9000/on-borrow";
      mustSucceed = false;
      async = false;
    };
  };

  # Redis with persistence enabled
  services.redis.servers."ip-allocator" = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";

    # Data directory for persistence
    # Data will be stored in /var/lib/redis-ip-allocator/
    settings = {
      # RDB Snapshots (point-in-time snapshots)
      # Save after 900 sec (15 min) if at least 1 key changed
      # Save after 300 sec (5 min) if at least 10 keys changed
      # Save after 60 sec if at least 10000 keys changed
      save = "900 1 300 10 60 10000";

      # AOF (Append Only File) for better durability
      appendonly = "yes";

      # Sync to disk every second (good balance of performance/durability)
      # Options: "always" (safest), "everysec" (recommended), "no" (fastest)
      appendfsync = "everysec";

      # Maximum memory (optional, adjust based on your needs)
      maxmemory = "256mb";
      maxmemory-policy = "noeviction";  # Don't evict keys, return errors instead
    };
  };

  # Ensure Redis starts before ip-allocator-webserver
  systemd.services.ip-allocator-webserver = {
    after = [ "redis-ip-allocator.service" ];
    wants = [ "redis-ip-allocator.service" ];
  };
}
