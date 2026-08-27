{
  description = "Homelab IaC devshell (OpenTofu + Ansible)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              opentofu
              ansible
              ansible-lint
              yamllint
              # hvac backs community.hashi_vault's lookups: without it the roles
              # cannot read their secrets out of OpenBao at play time.
              python3Packages.hvac
            ];

            # On macOS, Ansible's forked workers crash ("A worker was found in a
            # dead state") as soon as a lookup opens a TLS connection, the
            # OpenBao lookups do exactly that. This is the documented escape.
            OBJC_DISABLE_INITIALIZE_FORK_SAFETY = "YES";

            # Banner and warnings go to stderr so they never corrupt piped stdout
            # (e.g. `tofu … -json`).
            shellHook = ''
              echo "homelab IaC devshell, tofu $(tofu version | head -1 | cut -d' ' -f2), ansible $(ansible --version | head -1 | cut -d' ' -f3 | tr -d ']')" >&2

              # Bootstrap material lives outside the repository. A file that
              # opens the lab does not belong in a working tree, and least of
              # all in one that is published.
              export HOMELAB_SECRETS="''${HOMELAB_SECRETS:-$HOME/.config/homelab}"
              if [ ! -d "$HOMELAB_SECRETS" ]; then
                echo "⚠️  HOMELAB_SECRETS not found: $HOMELAB_SECRETS" >&2
              fi

              # The OpenBao tokens are periodic, which means renewable forever and
              # dead if nobody renews them. Both silently expired down to seven
              # days once already. Two seconds of network, never fatal, never
              # blocking when the lab is unreachable.
              if [ -r "$HOMELAB_SECRETS/openbao-ansible-token.json" ]; then
                ttl=$(
                  tok=$(python3 -c "import json;print(json.load(open('$HOMELAB_SECRETS/openbao-ansible-token.json'))['auth']['client_token'])" 2>/dev/null) &&
                  curl -s --max-time 2 --cacert "$HOMELAB_SECRETS/homelab-root-ca.pem" \
                    -H "X-Vault-Token: $tok" \
                    https://10.10.25.10:8200/v1/auth/token/lookup-self 2>/dev/null |
                    python3 -c "import json,sys;print(json.load(sys.stdin)['data']['ttl'])" 2>/dev/null
                ) || true
                if [ -n "''${ttl:-}" ] && [ "$ttl" -lt 864000 ] 2>/dev/null; then
                  echo "⚠️  OpenBao ansible token: $((ttl / 86400)) days left - ./scripts/vault-renew-tokens.sh" >&2
                fi
              fi
            '';
          };
        });
    };
}
