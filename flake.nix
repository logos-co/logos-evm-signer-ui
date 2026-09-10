{
  description = "Logos signer UI — the only surface that renders what is to be signed and takes the vault password.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The only REQUIRED module dependency, deliberately: this plugin cannot ask
    # anyone what an intent MEANS — it renders the lines the keystore authored,
    # and section 3 is decoded from those very lines by a linked-in library.
    keystore_module = {
      url = "github:logos-co/logos-evm-keystore-module";
      # Without the follows it drags its own module-builder, and a skewed generated
      # ABI segfaults the module inside provider init.
      inputs.logos-module-builder.follows = "logos-module-builder";
    };

    # OPTIONAL, and the one thing this plugin does ask another module. It can name
    # the address being signed to and give its decimals — a NAME, never a check of
    # the code, kept out of the tiers below and labelled with the list that
    # answered. Absent is a normal state: the sheet is then exactly what it was.
    token_list_module = {
      url = "github:logos-co/logos-evm-token-list-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };

    # Offline calldata decoding, linked in as a static archive. A library, not a
    # module: nothing is asked of the network, so the TIERS the human reads still
    # depend on this plugin alone.
    logos-tx-decoder = {
      url = "github:logos-co/logos-tx-decoder";
      # It builds the archive against logos-module-builder.inputs.nixpkgs; without the
      # follows that is a SECOND nixpkgs, and the .a is linked into this plugin.
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # A STATIC archive, deliberately. The builder copies every *.so/*.dylib an
      # external library ships into the plugin's lib/, and ui-host then tries to
      # load each file there as a Qt plugin — that is what broke
      # package_manager_ui. A .a is linked in and copied nowhere.
      externalLibInputs = {
        logos_tx_decoder = {
          input = inputs.logos-tx-decoder;
          packages.default = "logos_tx_decoder";
        };
      };
    };
}
