{
  description = "NixOS router fleet: one module set, one generated vars file per site, deployed with deploy-rs";

  inputs = {
    # Stable release (supported until 2026-12-31); Renovate proposes the next one.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Site data: <site>/vars.nix (sets `router.*`, schema in modules/options/), rendered by
    # Pulumi and injected by ./router (--override-input). Default: the fixtures. Copied to the
    # Nix store: never secrets.
    sites = {
      url = "path:./tests/sites";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      disko,
      sites,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # The sites of a folder of site data: one directory per site, holding its vars.nix.
      namesIn = dir: lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));
      siteNames = namesIn sites;

      # Hand-written hardware/boot profiles: hardware/<profile>.nix, chosen per site by
      # router.hardware.profile (modules/options/site.nix reads the same directory for its enum).
      hardwareProfile = name: ./hardware + "/${name}.nix";

      # Where Nix runs: the podman container on the Mac (aarch64-linux), CI runners and the
      # routers (x86_64-linux).
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];

      # The site's router.* values, evaluated on their own (cheap: no nixpkgs needed)
      # so the flake can pick the hardware profile and the deploy target statically.
      siteCfg =
        vars:
        (lib.evalModules {
          modules = [
            ./modules/options
            vars
          ];
          specialArgs = { inherit lib; };
        }).config.router;

      mkHost =
        dir: site:
        let
          vars = dir + "/${site}/vars.nix";
        in
        lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            ./modules
            vars
            (hardwareProfile (siteCfg vars).hardware.profile)
            (
              { config, ... }:
              {
                assertions = [
                  {
                    assertion = config.router.site.name == site;
                    message = "router.site.name (${config.router.site.name}) must equal the site directory name (${site})";
                  }
                ];
              }
            )
          ];
        };

      hostsIn = dir: lib.genAttrs (namesIn dir) (mkHost dir);

      # deploy-rs as packaged in nixpkgs (in cache.nixos.org: nothing to compile), with the
      # flake input's lib on top (as its README describes): `deploy` and the activation tool on
      # the router are then the same package.
      deployLib =
        (import nixpkgs {
          system = "x86_64-linux";
          overlays = [
            deploy-rs.overlays.default
            (_: prev: {
              deploy-rs = {
                inherit (nixpkgs.legacyPackages.x86_64-linux) deploy-rs;
                inherit (prev.deploy-rs) lib;
              };
            })
          ];
        }).deploy-rs.lib;
      siteCfgOf = site: siteCfg (sites + "/${site}/vars.nix");
      deployableSites = lib.filter (s: (siteCfgOf s).meta.deployable) siteNames;
      # Sort key of the deploy order: meta.deployOrder, sites without one last (the sort is
      # stable, so ties stay sorted by name).
      deployRank =
        site:
        let
          order = (siteCfgOf site).meta.deployOrder;
        in
        if order == null then 9223372036854775807 else order;
    in
    {
      # One configuration per directory under `sites`.
      nixosConfigurations = hostsIn sites;

      # `./router sites`, one line each: "<name> deployable=<bool> mgmt=<address>" (from the
      # site data alone, no nixpkgs), in deploy order (meta.deployOrder; none last, by name).
      routerSites = lib.concatMapStrings (
        site:
        let
          r = siteCfgOf site;
        in
        "${site} deployable=${lib.boolToString r.meta.deployable} mgmt=${r.mgmt.address}\n"
      ) (lib.sortOn deployRank siteNames);

      # `./router` connects to a deployable site with this: "<mgmt address>[ <host key>]" (with
      # a pinned host key, mgmt.hostKey, it is the site's known_hosts line).
      routerTarget = lib.genAttrs deployableSites (
        site:
        let
          inherit (siteCfgOf site) mgmt;
        in
        toString ([ mgmt.address ] ++ lib.optional (mgmt.hostKey != null) mgmt.hostKey)
      );

      # `./router dump <site>`: the parts of a site's configuration that matter (tests/dump.nix).
      routerDump = lib.mapAttrs (
        _: system: import ./tests/dump.nix system.config
      ) self.nixosConfigurations;

      # `deploy .#<site>` (use ./router deploy <site>). The first install of a new box
      # is `nixos-anywhere` (./router install <site>), not deploy-rs.
      deploy.nodes = lib.genAttrs deployableSites (site: {
        hostname = (siteCfgOf site).mgmt.address;
        sshUser = "deploy";
        user = "root";
        # The router builds itself: the Mac's container is aarch64, and from CI it fetches
        # from cache.nixos.org directly instead of receiving the closure through the hub.
        remoteBuild = true;
        magicRollback = true;
        autoRollback = true;
        # Time for EVPN to come back after a deploy that restarts NetBird and FRR.
        confirmTimeout = 180;
        profiles.system.path = deployLib.activate.nixos self.nixosConfigurations.${site};
      });

      # tests/checks.nix (deploy-rs' own checks would build every router system).
      checks = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./tests/checks.nix {
          inherit pkgs lib;
          configurations = self.nixosConfigurations;
          # The eval tests always use the fixtures, whatever `sites` is overridden with.
          fixtures = hostsIn ./tests/sites;
          inherit (self) deploy;
          deploySchema = deploy-rs + "/interface.json";
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              (lib.fileset.fileFilter (f: f.hasExt "nix") ./.)
              ./statix.toml
              ./router
              ./nx
              ./secrets-sync.sh
            ];
          };
        }
      );

      # `nix fmt` (./router fmt): nixfmt (RFC 166, default settings) over the tree; the `lint`
      # check runs the same nixfmt read-only. Root = this flake (works without git).
      formatter = lib.genAttrs systems (
        system:
        nixpkgs.legacyPackages.${system}.nixfmt-tree.override {
          settings = {
            tree-root-file = "flake.nix";
          };
        }
      );

      devShells = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.deploy-rs
              pkgs.nixos-anywhere
              pkgs.openssh # ssh/nix copy to the router (also inside the ./nx container)
              pkgs.git
              pkgs.nixfmt
            ];
          };
        }
      );
    };
}
