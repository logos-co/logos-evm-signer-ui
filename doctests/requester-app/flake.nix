{
  description = "signer_probe_app — doc-test fixture: the app that owns the requesting module.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The requesting module, which lives beside this fixture in the same repo.
    # `?dir=` rather than a relative path: a relative path input is refused in
    # pure evaluation, and CI resolves this repo by URL anyway.
    signer_probe = {
      url = "github:logos-co/logos-evm-signer-ui?dir=doctests/requester";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
