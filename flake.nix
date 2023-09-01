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

      mozillaConfigOverride = pkg: pkg.overrideAttrs (old: {
        buildCommand = old.buildCommand + ''
          # they will complain about not being able to read configuration
          # for some reason it can find autoconfig.js, but not mozilla.cfg
          # it wasn't being used for anything anyways, though
          find $out -name "autoconfig.js" -exec rm {} \;
          # rm $out/lib/*/defaults/pref/autoconfig.js
        '';
      });

      thunderbird = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = mozillaConfigOverride pkgs.thunderbird;

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

            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              # TODO: can we just take the firefox subdirectory
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

          app.package = mozillaConfigOverride pkgs.firefox;

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

            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              # TODO: can we just take the thunderbird subdirectory
              (sloth.concat' sloth.homeDir "/.mozilla")
              (sloth.concat' (sloth.env "XDG_CACHE_HOME") "/.mozilla")
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
            bind.ro = [
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

              (sloth.concat' sloth.homeDir "/.Xauthority")

            ];
            bind.dev = [
            # ???
              "/dev/dri"
            ];
          };
        };
      };
      chromium = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.chromium;

          dbus = {
            enable = true;
            # copied from the flatpak manifest
            # SEE: https://github.com/flathub/org.chromium.Chromium/blob/master/org.chromium.Chromium.yaml
            policies = {
              # should be system-talk
              # SEE: https://github.com/nixpak/nixpak/issues/6
              "org.bluez" = "talk";
              "org.freedesktop.Avahi" = "talk";
              "org.freedesktop.UPower" = "talk";

              "com.canonical.AppMenu.Registrar" = "talk";
              "org.freedesktop.FileManager1" = "talk";
              "org.freedesktop.Notifications" = "talk";
              "org.freedesktop.ScreenSaver" = "talk";
              "org.freedesktop.secrets" = "talk";
              "org.kde.kwalletd5" = "talk";
              "org.gnome.SessionManager" = "talk";
              "org.mpris.MediaPlayer2.chromium.*" = "own";

              # not in manifest, but will use filepicker
              "org.freedesktop.portal.*" = "talk";
            };
          };

          flatpak.appId = "org.chromium.Chromium";

          etc.sslCertificates.enable = true;

          bubblewrap = {
            network = true;
            shareIpc = true;

            # so it can create a socket
            tmpfs = [ "/tmp" ];

            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/chromium")
              (sloth.concat' (sloth.env "XDG_CACHE_HOME") "/chromium")
              (sloth.concat' sloth.homeDir "/Downloads")
              "/run/.heim_org.h5l.kcm-socket"
            ];
            bind.ro = [
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
              # (sloth.concat' sloth.homeDir "/.nix-profile")

              (sloth.concat' sloth.homeDir "/.Xauthority")

            ];
            bind.dev = [
            # ???
              "/dev/dri"
            ];
          };
        };
      };
      signal = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.signal-desktop;

          dbus = {
            enable = true;
            # copied from the flatpak manifest
            # SEE: https://github.com/flathub/org.signal.Signal/blob/master/org.signal.Signal.yaml
            policies = {
              # We need to send notifications
              "org.freedesktop.Notifications" = "talk";
              "org.gnome.Mutter.IdleMonitor" = "talk";
              "org.kde.StatusNotifierWatcher" = "talk";
              "com.canonical.AppMenu.Registrar" = "talk";
              "com.canonical.indicator.application" = "talk";
              "org.ayatana.indicator.application" = "talk";
              # Allow running in background
              "org.freedesktop.portal.Background" = "talk";
              # Allow advanced input methods
              "org.freedesktop.portal.Fcitx" = "talk";
              # This is needed for the tray icon
              "org.kde.*" = "own";
            };
          };

          flatpak.appId = "org.signal.Signal";

          etc.sslCertificates.enable = true;

          bubblewrap = {
            network = true;
            shareIpc = true;

            bind.rw = [
              # double check if this is necessary
              (sloth.env "XDG_RUNTIME_DIR")
              # (sloth.concat' (sloth.env "XDG_CONFIG_HOME") "/Signal")
              # (sloth.concat' sloth.homeDir "/Downloads")
              sloth.homeDir
            ];
            bind.ro = [
              # TODO: replace with nixpak-specific font config?
              "/etc/fonts"

              # ???
              "/etc/resolv.conf"
              # "/sys/devices/pci0000:00"
              # for hardware acceleration maybe?
              # "/sys/bus/pci"

              # pulseaudio socket
              # is this necessary? we already bind a containing directory rw
              (sloth.concat' (sloth.env "XDG_RUNTIME_DIR") "/pulse/native")
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
      chromium = chromium.config.env;
      signal = signal.config.env;

      shell = (mkNixPak {
        config = { sloth, pkgs, ... }: {
          app.package = pkgs.bash;
        };
      }).config.script;
    };
  };
}
