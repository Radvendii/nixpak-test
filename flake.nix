{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
    
  outputs = { self, nixpkgs, nixpak }: 
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
  in
  {
    nixpakModules = {
      # There are a bunch of options that seem common for gui apps. For now,
      # support for wayland, but no support for x (access to the x socket is
      # actually quite a security problem)
      gui = { sloth, config, ... }: {
        options.gui = {
          enable = lib.mkEnableOption "defaults for gui apps";
          hardwareAcceleration.enable =
            lib.mkEnableOption "things needed for hardware acceleration" // { default = true; }; 
        };
        config = lib.mkIf config.gui.enable {
          bubblewrap = lib.mkMerge [{
            bind.ro = [ 
              # Fonts. SEE: https://github.com/nixpak/nixpak/issues/28
              "/etc/fonts"
              # cursor icons
              "/run/current-system/sw/share/icons"
              # timezone. often needed and pretty harmless
              "/etc/localtime"
              # access to displays (for wayland also, I think)
              (sloth.concat' sloth.homeDir "/.Xauthority")
            ];
          } {
            bind = lib.mkIf config.gui.hardwareAcceleration.enable {
              ro = [
                "/sys/bus/pci"
                # not sure if this is needed
                # "/sys/devices/pci0000:00"
              ];
              dev = [ "/dev/dri" ];
            };
          }];
        };
      };
      network = { config, ... }: {
        config = lib.mkIf config.bubblewrap.network {
          # DNS is almost always necessary if you want network access
          bubblewrap.bind.ro = [
            "/etc/resolv.conf"
          ];
          # we want secure network access
          etc.sslCertificates.enable = true;
        };
      };
      peripherals = { config, sloth, ... }: {
        options = {
          peripherals.enable = lib.mkEnableOption "access to peripherals";
        };
        config = lib.mkIf config.peripherals.enable {
          bubblewrap.bind = {
            ro = [
              # pulseaudio socket
              (sloth.concat' (sloth.runtimeDir) "/pulse/native")
            ];
            # most manifests mount /dev, but this seems to suffice.
            dev = [
              # FIXME: none of these work.
              #        flatpaks get it working by using `--device=all`
              #        but it's not clear what that translates to in bubblewrap arguments
              # "/dev/dri"
              # video capture (webcam)
              # "/dev/video0"
              # "/dev/video1"
              # "/dev/video2"
              # "/dev/video3"
              # "/dev/video4"
              # "/dev/video5"
              # "/dev/video6"
              # "/dev/video7"
              # "/dev/video8"
              # "/dev/video9"
              # "/dev/v4l"
              # "/dev"
            ];
          };
        };
      };
    };
    checks = self.packages;
    packages.${system} = let
      pkgs = nixpkgs.legacyPackages.${system};

      mkNixPak = args@{ config, ... }:
        nixpak.lib.nixpak {
          inherit (pkgs) lib;
          inherit pkgs;
        } (args // {
          config = {
            imports = (builtins.attrValues self.nixpakModules) ++ [ config ];
          };
        });

      mozillaConfigOverride = pkg: pkg.overrideAttrs (old: {
        # `firefox` and `thunderbird` are defined weirdly, which is why we
        # override `buildCommand` rather than setting `postInstall`
        # SEE: https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/browsers/firefox/wrapper.nix
        buildCommand = old.buildCommand + ''
          # they will complain about not being able to read configuration
          # for some reason it can find autoconfig.js, but not mozilla.cfg
          # it wasn't being used for anything anyways, though
          find $out -name "autoconfig.js" -exec rm {} \;
        '';
      });

      # MANIFEST: https://github.com/flathub/org.mozilla.Thunderbird/blob/master/org.mozilla.Thunderbird.json#L13
      thunderbird = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = mozillaConfigOverride pkgs.thunderbird;
          flatpak.appId = "org.mozilla.Thunderbird";

          gui.enable = true;

          dbus = {
            enable = true;
            policies = {
              "org.freedesktop.DBus" = "talk";
              "org.ally.Bus" = "talk";
              "org.freedesktop.Notifications" = "talk";
              "org.freedesktop.portal.*" = "talk";
              "org.mozilla.thunderbird_default.*" = "own";
            };
          };

          bubblewrap = {
            network = true;
            shareIpc = true;

            bind.rw = [
              # double check if this is necessary
              # (sloth.runtimeDir)
              # there are possibly extensions in here so we can't just take the
              # relevant subdirectory
              (sloth.concat' sloth.homeDir "/.mozilla")
              # TODO: is this a thing?
              (sloth.concat' sloth.homeDir "/.thunderbird")
              (sloth.concat' sloth.xdgCacheHome "/.mozilla")
              # download without a file picker prompt
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
          };
        };

      };

      # MANIFEST: https://hg.mozilla.org/mozilla-central/file/tip/taskcluster/docker/firefox-flatpak/runme.sh
      firefox = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = mozillaConfigOverride pkgs.firefox;
          flatpak.appId = "org.mozilla.Firefox";

          gui.enable = true;

          dbus = {
            enable = true;
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

          bubblewrap = {
            network = true;
            shareIpc = true;

            bind.rw = [
              # XXX: double check if this is necessary
              # sloth.runtimeDir
              # there are possibly extensions in here so we can't just take the
              # relevant subdirectory
              (sloth.concat' sloth.homeDir "/.mozilla")
              (sloth.concat' (sloth.xdgCacheHome) "/mozilla/firefox")
              # download without a file picker prompt
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
          };
        };
      };

      # MANIFEST: https://github.com/flathub/org.chromium.Chromium/blob/master/org.chromium.Chromium.yaml
      chromium = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.chromium;

          gui.enable = true;

          dbus = {
            enable = true;
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

          bubblewrap = {
            network = true;
            shareIpc = true;

            # so it can create a socket
            tmpfs = [ "/tmp" ];

            bind.rw = [
              # double check if this is necessary
              # (sloth.runtimeDir)
              (sloth.concat' (sloth.xdgConfigHome) "/chromium")
              (sloth.concat' (sloth.xdgCacheHome) "/chromium")
              # download without a file picker prompt
              (sloth.concat' sloth.homeDir "/Downloads")
              "/run/.heim_org.h5l.kcm-socket"
            ];
            bind.ro = [
              # pulseaudio socket
              # is this necessary? we already bind a containing directory rw
              (sloth.concat' (sloth.runtimeDir) "/pulse/native")
            ];
          };
        };
      };
      # MANIFEST: https://github.com/flathub/org.signal.Signal/blob/master/org.signal.Signal.yaml
      signal = mkNixPak {
        config = { sloth, pkgs, ... }: {

          app.package = pkgs.signal-desktop;

          gui.enable = true;

          dbus = {
            enable = true;
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

              # FIXME: signal doesn't know how to use this
              # "org.freedesktop.portal.*" = "talk";
            };
          };

          flatpak.appId = "org.signal.Signal";

          bubblewrap = {
            network = true;
            shareIpc = true;

            bind.rw = [
              # double check if this is necessary
              # (sloth.runtimeDir)
              (sloth.concat' (sloth.xdgConfigHome) "/Signal")
              # download without a file picker prompt
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
            bind.ro = [
              # pulseaudio socket
              # is this necessary? we already bind a containing directory rw
              (sloth.concat' (sloth.runtimeDir) "/pulse/native")
            ];
          };
        };
      };
    in {
      firefox = firefox.config.env.override {
        # TODO: upstream. this should be done by default
        meta.mainProgram = pkgs.firefox.meta.mainProgram;
      };
      thunderbird = thunderbird.config.env.override {
        meta.mainProgram = pkgs.thunderbird.meta.mainProgram;
      };
      chromium = chromium.config.env.override {
        meta.mainProgram = pkgs.chromium.meta.mainProgram;
      };
      signal = signal.config.env.override {
        meta.mainProgram = "signal-desktop";
      };

      shell = (mkNixPak {
        config = { sloth, pkgs, ... }: {
          app.package = pkgs.bash;
        };
      }).config.script;
    };
  };
}
