# █▄░█ █▀▀ ▀█▀ █░█░█ █▀█ █▀█ █▄▀ ▀
# █░▀█ ██▄ ░█░ ▀▄▀▄▀ █▄█ █▀▄ █░█ ▄
# -- -- -- -- -- -- -- -- -- -- --

{ config, pkgs, ... }: {
  networking = {
    interfaces = {
      ens3.ipv4.addresses = [{
        address = "89.110.66.188";
        prefixLength = 24;
      }];
    };
    defaultGateway = "89.110.66.1";
    nameservers = [ "8.8.8.8" "1.1.1.1" ];
    hostName = "vps-vpn";
  };
}
