{ pkgs ? import <nixpkgs> {} }:
let
  # provides "echo-shortcuts"
  nix_shortcuts = import (pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/whacked/setup/ce9fe9be8e42db9ce003772099d08395358efe8c/bash/nix_shortcuts.nix.sh";
    hash = "sha256-uK+Fgwr6iWXbfi/itJGELzkWqGZsQ8HFpfc+ztGSF98=";
  }) { inherit pkgs; };
in pkgs.mkShell {
  buildInputs = [
    pkgs.nats-server
    pkgs.natscli    # the "nats" CLI: the terminal participant
  ];  # join lists with ++

  nativeBuildInputs = [
  ];

  shellHook = nix_shortcuts.shellHook + ''
    export MC_HOME="$(pwd)"
    export MC_NATS_URL="nats://127.0.0.1:4223"
    export PATH="$MC_HOME/bin:$PATH"

    alias bus-start='bus-start'
    alias bus-stop='bus-stop'
    alias bus-status='bus-status'
  '' + ''
    echo-shortcuts ${__curPos.file}
    echo "MC_HOME=$MC_HOME  MC_NATS_URL=$MC_NATS_URL"
  '';  # join strings with +
}
