# Basic example: Enable ip-allocator-webserver with minimal configuration
#
# This example shows the simplest way to enable the service.
# It uses default settings: port 8000, local Redis at redis://127.0.0.1:6379/

{ config, pkgs, ... }:

{
  services.ip-allocator-webserver = {
    enable = true;
    package = pkgs.ip-allocator-webserver;
  };

  # Enable Redis (required by ip-allocator-webserver)
  services.redis.servers."".enable = true;
}
