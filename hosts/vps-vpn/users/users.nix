# █░█ █▀ █▀▀ █▀█ █▀ ▀
# █▄█ ▄█ ██▄ █▀▄ ▄█ ▄
# -- -- -- -- -- -- -

{ config, pkgs, ... }: {
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users = { 
    roman = {
      isNormalUser = true;
      description = "papa";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      packages = with pkgs; [];
    };
    # ... add more users here
  };
}
