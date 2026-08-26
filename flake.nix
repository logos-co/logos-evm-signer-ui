{
  description = "Logos signer UI — the only surface that renders what is to be signed and takes the vault password.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The ONLY dependency, deliberately. This plugin has no client for any
    # wallet, chain, RPC or token-list module, so it cannot decode an intent
    # even if it wanted to — it renders the lines the keystore authored.
    # TEMPORARY: ?ref= while the approval surface this plugin approves against
    # lives on a branch. REVERT to the plain URL when
    # logos-evm-keystore-module#6 merges -- keystore's main has no
    # request_approval / acknowledge / approve, so the plain URL cannot build.
    keystore_module.url = "github:logos-co/logos-evm-keystore-module?ref=feat/keystore-hardening";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
