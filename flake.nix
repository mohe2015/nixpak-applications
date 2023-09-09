{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
    
  outputs = { self, nixpkgs, nixpak }: {
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      mkNixPak = nixpak.lib.nixpak {
        inherit (pkgs) lib;
        inherit pkgs;
      };

      sandboxed-chromium = mkNixPak {
        config = { sloth, ... }: {
          # nix shell .#sandboxed-chromium --command chromium
          app.package = pkgs.writeShellScriptBin "chromium"
          ''
          ${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland
          '';
          app.binPath = "bin/chromium";
          flatpak.appId = "org.nixos.Chromium";
          bubblewrap.sockets.wayland = true;
          bubblewrap.sockets.pipewire = true;
          bubblewrap.shareIpc = true;
          fonts.enable = true;
          # https://github.com/flathub/org.chromium.Chromium/blob/16ab27d32b3aa2c7d12ff392ca5f782c9eb27ec9/org.chromium.Chromium.yaml#L21
          bubblewrap.bind.rw = [
            (sloth.env "XDG_RUNTIME_DIR")
          ];
          bubblewrap.bind.ro = [
            "/run/dbus"
          ];
          bubblewrap.network = true;
          bubblewrap.tmpfs = ["/tmp"];
        };
      };

      sandboxed-hello = mkNixPak {
        config = { sloth, ... }: {

          # the application to isolate
          app.package = pkgs.hello;

          # path to the executable to be wrapped
          # this is usually autodetected but
          # can be set explicitly nonetheless
          app.binPath = "bin/hello";

          # enabled by default, flip to disable
          # and to remove dependency on xdg-dbus-proxy
          dbus.enable = true;

          # same usage as --see, --talk, --own
          dbus.policies = {
            "org.freedesktop.DBus" = "talk";
            "ca.desrt.dconf" = "talk";
          };

          # needs to be set for Flatpak emulation
          # defaults to com.nixpak.${name}
          # where ${name} is generated from the drv name like:
          # hello -> Hello
          # my-app -> MyApp
          flatpak.appId = "org.myself.HelloApp";

          bubblewrap = {

            # disable all network access
            network = false;

            # lists of paths to be mounted inside the sandbox
            # supports runtime resolution of environment variables
            # see "Sloth values" below
            bind.rw = [
              (sloth.concat' sloth.homeDir "/Documents")
              (sloth.env "XDG_RUNTIME_DIR")
              # a nested list represents a src -> dest mapping
              # where src != dest
              [
                (sloth.concat' sloth.homeDir "/.local/state/nixpak/hello/config")
                (sloth.concat' sloth.homeDir "/.config")
              ]
            ];
            bind.ro = [
              (sloth.concat' sloth.homeDir "/Downloads")
            ];
            bind.dev = [
              "/dev/dri"
            ];
          };
        };
      };
    in {
      # Just the wrapped /bin/${mainProgram} binary
      hello = sandboxed-hello.config.script;

      sandboxed-chromium = sandboxed-chromium.config.env;

      # A symlinkJoin that resembles the original package,
      # except the main binary is swapped for the
      # wrapper script, as are textual references
      # to the binary, like in D-Bus service files.
      # Useful for GUI apps.
      hello-env = sandboxed-hello.config.env;
    };
  };
}
