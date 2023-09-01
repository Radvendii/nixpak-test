{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpak = {
      url = "github:max-privatevoid/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
    
  outputs = { self, nixpkgs, nixpak }: 
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
  in
  {
    nixosConfigurations.test = lib.nixosSystem {
      inherit system;
      modules = [({pkgs, modulesPath, ...}: {
        imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];
        virtualisation.graphics = true;
        services.xserver = {
          enable = true;
          displayManager.gdm.enable = true;
          desktopManager.gnome.enable = true;
        };
        environment.systemPackages = [
          self.packages.${system}.firefox
        ];
      })];
    };
    packages.${system} = let
      pkgs = nixpkgs.legacyPackages.${system};

      mkNixPak = nixpak.lib.nixpak {
        inherit (pkgs) lib;
        inherit pkgs;
      };

      thunderbird = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.thunderbird;

          dbus = {
            enable = true;
            # copied from the flatpak manifest
            # SEE: https://github.com/flathub/org.mozilla.Thunderbird/blob/master/org.mozilla.Thunderbird.json#L13
            policies = {
              "org.freedesktop.DBus" = "talk";
              "org.ally.Bus" = "talk";
              "org.freedesktop.Notifications" = "talk";
              "org.freedesktop.portal.*" = "talk";
              "org.mozilla.thunderbird_default.*" = "own";
            };
          };

          flatpak.appId = "org.mozilla.Thunderbird";

          etc.sslCertificates.enable = true;

          bubblewrap = {
            network = true;
            shareIpc = true;

            # lists of paths to be mounted inside the sandbox
            # supports runtime resolution of environment variables
            # see "Sloth values" below
            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              # TODO: can we just take the firefox subdirectory
              # FIXME: still complains about not being able to read configuration
              (sloth.concat' sloth.homeDir "/.mozilla")
              (sloth.concat' sloth.homeDir "/.thunderbird")
              (sloth.concat' (sloth.env "XDG_CACHE_HOME") "/.mozilla")
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
            bind.ro = [
              # (sloth.concat' sloth.homeDir "/Downloads")
              # TODO: replace with nixpak-specific font config?
              "/etc/fonts"

              # ???
              "/etc/resolv.conf"
              "/sys/devices/pci0000:00"
              # for hardware acceleration maybe?
              "/sys/bus/pci"

              # pulseaudio socket
              # is this necessary? we already bind a containing directory rw
              (sloth.concat' (sloth.env "XDG_RUNTIME_DIR") "/pulse/native")

              # maybe needed for anything configured by home manager??
              (sloth.concat' sloth.homeDir "/.nix-profile")

              (sloth.concat' sloth.homeDir "/.Xauthority")
            ];
            bind.dev = [
            # ???
              "/dev/dri"
            ];
          };
        };

      };

      firefox = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.firefox;

          dbus = {
            enable = true;
            # copied from the flatpak manifest
            # SEE: https://hg.mozilla.org/mozilla-central/file/tip/taskcluster/docker/firefox-flatpak/runme.sh
            # TODO: the organization of these should be flipped.
            # talk = [
            #   "org.freedesktop.DBus"
            #   "or.ally.Bus"
            #   ...
            # ];
            policies = {
              "org.freedesktop.FileManager1" = "talk";
              "org.freedesktop.DBus" = "talk";
              "org.ally.Bus" = "talk";
              "org.gnome.SessionManager" = "talk";
              "org.freedesktop.ScreenSaver" = "talk";
              "org.freedesktop.Notifications" = "talk";
              "org.freedesktop.portal.*" = "talk";
              "org.gtk.vfs.*" = "talk";
              "ca.desrt.dconf" = "talk";
              "org.mpris.MediaPlayer2.firefox.*" = "own";
              "org.mozilla.firefox.*" = "own";
              "org.mozilla.firefox_beta.*" = "own";
            };
          };

          flatpak.appId = "org.mozilla.Firefox";

          etc.sslCertificates.enable = true;

          bubblewrap = {
            network = true;
            shareIpc = true;

            # lists of paths to be mounted inside the sandbox
            # supports runtime resolution of environment variables
            # see "Sloth values" below
            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              # TODO: can we just take the firefox subdirectory
              # FIXME: still complains about not being able to read configuration
              (sloth.concat' sloth.homeDir "/.mozilla")
              (sloth.concat' (sloth.env "XDG_CACHE_HOME") "/.mozilla")
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
            bind.ro = [
              # (sloth.concat' sloth.homeDir "/Downloads")
              # TODO: replace with nixpak-specific font config?
              "/etc/fonts"

              # ???
              "/etc/resolv.conf"
              "/sys/devices/pci0000:00"
              # for hardware acceleration maybe?
              "/sys/bus/pci"

              # pulseaudio socket
              # is this necessary? we already bind a containing directory rw
              (sloth.concat' (sloth.env "XDG_RUNTIME_DIR") "/pulse/native")

              # maybe needed for anything configured by home manager
              (sloth.concat' sloth.homeDir "/.nix-profile")

              (sloth.concat' sloth.homeDir "/.Xauthority")

            ];
            bind.dev = [
            # ???
              "/dev/dri"
            ];
          };
        };
      };
    in {
      firefox = firefox.config.env;
      thunderbird = thunderbird.config.env;

      shell = (mkNixPak {
        config = { sloth, pkgs, ... }: {
          app.package = pkgs.bash;
        };
      }).config.script;
    };
  };
}
