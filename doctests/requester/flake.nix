{
  description = "signer_probe — doc-test fixture: the module that asks for a signature.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Pinned to the commits that made the keystore a signer and added the manager.
    keystore_module = {
      url = "github:logos-co/logos-evm-keystore-module/e4c6fcd39411f0ed52083f0a7fb2701e742f81f1";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    signer_manager_module = {
      url = "github:logos-co/logos-signer-manager-module/1a385f4e41ef54f388a192037bd9d9aa7165a505";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.keystore_module.follows = "keystore_module";
    };
    # A signer that behaves like a device: a doc-test fixture beside the manager.
    mock_device_signer = {
      url = "github:logos-co/logos-signer-manager-module/1a385f4e41ef54f388a192037bd9d9aa7165a505?dir=doctests/mock-device";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ self, logos-module-builder, ... }:
    let
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
    in
    {
      packages = nixpkgs.lib.genAttrs systems (system:
        (logos-module-builder.lib.mkLogosModule {
          src = ./.;
          configFile = ./metadata.json;
          flakeInputs = inputs;
        }).packages.${system});
    };
}
