{
  description = "Logos signer UI — the only surface that renders what is to be signed and takes the vault password.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The ONLY dependency, deliberately. This plugin has no client for any
    # wallet, chain, RPC or token-list module, so it cannot decode an intent
    # even if it wanted to — it renders the lines the keystore authored.
    keystore_module.url = "github:logos-co/logos-evm-keystore-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
