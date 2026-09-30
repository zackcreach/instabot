{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    bandit = buildMix rec {
      name = "bandit";
      version = "1.12.5";

      src = fetchHex {
        pkg = "bandit";
        version = "${version}";
        sha256 = "c5684ca062fa407cac115aec3256383f3e2ec9fdced7904d59cf5a7bb7ed6181";
      };

      beamDeps = [ hpax plug telemetry thousand_island websock ];
    };

    bcrypt_elixir = buildMix rec {
      name = "bcrypt_elixir";
      version = "3.3.2";

      src = fetchHex {
        pkg = "bcrypt_elixir";
        version = "${version}";
        sha256 = "471be5151874ae7931911057d1467d908955f93554f7a6cd1b7d804cac8cef53";
      };

      beamDeps = [ comeonin elixir_make ];
    };

    bypass = buildMix rec {
      name = "bypass";
      version = "2.1.0";

      src = fetchHex {
        pkg = "bypass";
        version = "${version}";
        sha256 = "d9b5df8fa5b7a6efa08384e9bbecfe4ce61c77d28a4282f79e02f1ef78d96b80";
      };

      beamDeps = [ plug plug_cowboy ranch ];
    };

    cc_precompiler = buildMix rec {
      name = "cc_precompiler";
      version = "0.1.11";

      src = fetchHex {
        pkg = "cc_precompiler";
        version = "${version}";
        sha256 = "3427232caf0835f94680e5bcf082408a70b48ad68a5f5c0b02a3bea9f3a075b9";
      };

      beamDeps = [ elixir_make ];
    };

    comeonin = buildMix rec {
      name = "comeonin";
      version = "5.5.1";

      src = fetchHex {
        pkg = "comeonin";
        version = "${version}";
        sha256 = "65aac8f19938145377cee73973f192c5645873dcf550a8a6b18187d17c13ccdb";
      };

      beamDeps = [];
    };

    cowboy = buildErlangMk rec {
      name = "cowboy";
      version = "2.19.0";

      src = fetchHex {
        pkg = "cowboy";
        version = "${version}";
        sha256 = "986dae81f99fcb78ef2d8efc21d738cee189410840eeaf32eca84ada81dcf6d4";
      };

      beamDeps = [ cowlib ranch ];
    };

    cowboy_telemetry = buildRebar3 rec {
      name = "cowboy_telemetry";
      version = "0.4.0";

      src = fetchHex {
        pkg = "cowboy_telemetry";
        version = "${version}";
        sha256 = "7d98bac1ee4565d31b62d59f8823dfd8356a169e7fcbb83831b8a5397404c9de";
      };

      beamDeps = [ cowboy telemetry ];
    };

    cowlib = buildRebar3 rec {
      name = "cowlib";
      version = "2.20.0";

      src = fetchHex {
        pkg = "cowlib";
        version = "${version}";
        sha256 = "7d41a0dd2c093041ff3779ac5fe8a1585a68ec7cb2dd1de0536bdd2452fd7ba1";
      };

      beamDeps = [];
    };

    db_connection = buildMix rec {
      name = "db_connection";
      version = "2.10.2";

      src = fetchHex {
        pkg = "db_connection";
        version = "${version}";
        sha256 = "510b14482330f1af6490a2fa0efd8d4f1435d1529b165647df22ac0f2df0fa93";
      };

      beamDeps = [ telemetry ];
    };

    decimal = buildMix rec {
      name = "decimal";
      version = "3.1.1";

      src = fetchHex {
        pkg = "decimal";
        version = "${version}";
        sha256 = "c5f25f2ced74a0587d03e6023f595db8e924c9d3922c8c8ffd9edfc4498cf1f6";
      };

      beamDeps = [];
    };

    dns_cluster = buildMix rec {
      name = "dns_cluster";
      version = "0.2.0";

      src = fetchHex {
        pkg = "dns_cluster";
        version = "${version}";
        sha256 = "ba6f1893411c69c01b9e8e8f772062535a4cf70f3f35bcc964a324078d8c8240";
      };

      beamDeps = [];
    };

    ecto = buildMix rec {
      name = "ecto";
      version = "3.14.2";

      src = fetchHex {
        pkg = "ecto";
        version = "${version}";
        sha256 = "25d60b8c816a07d19d85b80bdf60978bd8b102209dda198d768cd7c6745339a6";
      };

      beamDeps = [ decimal jason telemetry ];
    };

    ecto_sql = buildMix rec {
      name = "ecto_sql";
      version = "3.14.0";

      src = fetchHex {
        pkg = "ecto_sql";
        version = "${version}";
        sha256 = "f4d8d36faf294c9417b5a37ec7ac8217ee2abdef5fcf197ba690f361548d3949";
      };

      beamDeps = [ db_connection decimal ecto postgrex telemetry ];
    };

    elixir_make = buildMix rec {
      name = "elixir_make";
      version = "0.10.0";

      src = fetchHex {
        pkg = "elixir_make";
        version = "${version}";
        sha256 = "dc1f09fb7fa68866b886abd5f0f3c83553b1a19a52359a899e92af1bb3b31982";
      };

      beamDeps = [];
    };

    esbuild = buildMix rec {
      name = "esbuild";
      version = "0.10.0";

      src = fetchHex {
        pkg = "esbuild";
        version = "${version}";
        sha256 = "468489cda427b974a7cc9f03ace55368a83e1a7be12fba7e30969af78e5f8c70";
      };

      beamDeps = [ jason ];
    };

    expo = buildMix rec {
      name = "expo";
      version = "1.1.1";

      src = fetchHex {
        pkg = "expo";
        version = "${version}";
        sha256 = "5fb308b9cb359ae200b7e23d37c76978673aa1b06e2b3075d814ce12c5811640";
      };

      beamDeps = [];
    };

    file_system = buildMix rec {
      name = "file_system";
      version = "1.1.1";

      src = fetchHex {
        pkg = "file_system";
        version = "${version}";
        sha256 = "7a15ff97dfe526aeefb090a7a9d3d03aa907e100e262a0f8f7746b78f8f87a5d";
      };

      beamDeps = [];
    };

    finch = buildMix rec {
      name = "finch";
      version = "0.24.0";

      src = fetchHex {
        pkg = "finch";
        version = "${version}";
        sha256 = "33ba40069c3587c2f99f9125b766e19dad87d6d54be3c6961db2304df04cef00";
      };

      beamDeps = [ mime mint nimble_options nimble_pool telemetry ];
    };

    fine = buildMix rec {
      name = "fine";
      version = "0.1.6";

      src = fetchHex {
        pkg = "fine";
        version = "${version}";
        sha256 = "5638eb4495488e885ebec167fa57973e5c35e1a50c344eb7666c90ec1c4e3b12";
      };

      beamDeps = [];
    };

    gettext = buildMix rec {
      name = "gettext";
      version = "1.0.2";

      src = fetchHex {
        pkg = "gettext";
        version = "${version}";
        sha256 = "eab805501886802071ad290714515c8c4a17196ea76e5afc9d06ca85fb1bfeb3";
      };

      beamDeps = [ expo ];
    };

    hammer = buildMix rec {
      name = "hammer";
      version = "6.2.1";

      src = fetchHex {
        pkg = "hammer";
        version = "${version}";
        sha256 = "b9476d0c13883d2dc0cc72e786bac6ac28911fba7cc2e04b70ce6a6d9c4b2bdc";
      };

      beamDeps = [ poolboy ];
    };

    hpax = buildMix rec {
      name = "hpax";
      version = "1.1.0";

      src = fetchHex {
        pkg = "hpax";
        version = "${version}";
        sha256 = "0b8d0f05832f55571d65ac720f79bf8994138ffbb133209dc4685eae0ad456a8";
      };

      beamDeps = [];
    };

    idna = buildRebar3 rec {
      name = "idna";
      version = "7.1.0";

      src = fetchHex {
        pkg = "idna";
        version = "${version}";
        sha256 = "6ae959a025bf36df61a8cab8508d9654891b5426a84c44d82deaffd6ddf8c71f";
      };

      beamDeps = [];
    };

    imgproxy = buildMix rec {
      name = "imgproxy";
      version = "3.1.0";

      src = fetchHex {
        pkg = "imgproxy";
        version = "${version}";
        sha256 = "5abfe6777c95f8fb8e6b031ecfcfe3399b3327a76a9aa2e870af235d79b8081f";
      };

      beamDeps = [];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.5";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "b0c823996102bcd0239b3c2444eb00409b72f6a140c1950bc8b457d836b30684";
      };

      beamDeps = [ decimal ];
    };

    lazy_html = buildMix rec {
      name = "lazy_html";
      version = "0.1.13";

      src = fetchHex {
        pkg = "lazy_html";
        version = "${version}";
        sha256 = "9a8405d6785fe6f8423b86e0ec5f21806ef79941fe853eac3d14fbbb173c34e9";
      };

      beamDeps = [ cc_precompiler elixir_make fine ];
    };

    mime = buildMix rec {
      name = "mime";
      version = "2.0.7";

      src = fetchHex {
        pkg = "mime";
        version = "${version}";
        sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
      };

      beamDeps = [];
    };

    mint = buildMix rec {
      name = "mint";
      version = "1.11.0";

      src = fetchHex {
        pkg = "mint";
        version = "${version}";
        sha256 = "c6279ba2d6aa3a383a1d4cfbe7b59f42e6efd400f58d8e2acfeac48a438693ab";
      };

      beamDeps = [ hpax ];
    };

    nimble_options = buildMix rec {
      name = "nimble_options";
      version = "1.1.1";

      src = fetchHex {
        pkg = "nimble_options";
        version = "${version}";
        sha256 = "821b2470ca9442c4b6984882fe9bb0389371b8ddec4d45a9504f00a66f650b44";
      };

      beamDeps = [];
    };

    nimble_pool = buildMix rec {
      name = "nimble_pool";
      version = "1.1.0";

      src = fetchHex {
        pkg = "nimble_pool";
        version = "${version}";
        sha256 = "af2e4e6b34197db81f7aad230c1118eac993acc0dae6bc83bac0126d4ae0813a";
      };

      beamDeps = [];
    };

    oban = buildMix rec {
      name = "oban";
      version = "2.24.1";

      src = fetchHex {
        pkg = "oban";
        version = "${version}";
        sha256 = "ef8482472cf198554400b7f8e36a0ffee75c3a64de425d5c7ee625d271925ac7";
      };

      beamDeps = [ ecto_sql jason postgrex telemetry ];
    };

    phoenix = buildMix rec {
      name = "phoenix";
      version = "1.8.15";

      src = fetchHex {
        pkg = "phoenix";
        version = "${version}";
        sha256 = "7b83ed6b3d544f24a29277eab7f051be38b76f390bb511bb6ddb7ec6e8e05b95";
      };

      beamDeps = [ bandit jason phoenix_pubsub phoenix_template plug plug_cowboy plug_crypto telemetry websock_adapter ];
    };

    phoenix_ecto = buildMix rec {
      name = "phoenix_ecto";
      version = "4.7.0";

      src = fetchHex {
        pkg = "phoenix_ecto";
        version = "${version}";
        sha256 = "1d75011e4254cb4ddf823e81823a9629559a1be93b4321a6a5f11a5306fbf4cc";
      };

      beamDeps = [ ecto phoenix_html plug postgrex ];
    };

    phoenix_html = buildMix rec {
      name = "phoenix_html";
      version = "4.3.0";

      src = fetchHex {
        pkg = "phoenix_html";
        version = "${version}";
        sha256 = "3eaa290a78bab0f075f791a46a981bbe769d94bc776869f4f3063a14f30497ad";
      };

      beamDeps = [];
    };

    phoenix_live_dashboard = buildMix rec {
      name = "phoenix_live_dashboard";
      version = "0.8.7";

      src = fetchHex {
        pkg = "phoenix_live_dashboard";
        version = "${version}";
        sha256 = "3a8625cab39ec261d48a13b7468dc619c0ede099601b084e343968309bd4d7d7";
      };

      beamDeps = [ ecto mime phoenix_live_view telemetry_metrics ];
    };

    phoenix_live_reload = buildMix rec {
      name = "phoenix_live_reload";
      version = "1.7.0";

      src = fetchHex {
        pkg = "phoenix_live_reload";
        version = "${version}";
        sha256 = "dc9f44271aa6fc4ab7797f2aa374ba096ef2c87520586280eb095626b7387a68";
      };

      beamDeps = [ file_system phoenix ];
    };

    phoenix_live_view = buildMix rec {
      name = "phoenix_live_view";
      version = "1.1.33";

      src = fetchHex {
        pkg = "phoenix_live_view";
        version = "${version}";
        sha256 = "2030f7987f641a269634e021bcde9373e5dea993f9373e628a44da86b2330b6c";
      };

      beamDeps = [ jason lazy_html phoenix phoenix_html phoenix_template plug telemetry ];
    };

    phoenix_pubsub = buildMix rec {
      name = "phoenix_pubsub";
      version = "2.3.0";

      src = fetchHex {
        pkg = "phoenix_pubsub";
        version = "${version}";
        sha256 = "eec7be6e9cf02e2551d389b558402d6c637cd3973796326e7ba4bb03c6b2e91d";
      };

      beamDeps = [];
    };

    phoenix_template = buildMix rec {
      name = "phoenix_template";
      version = "1.1.0";

      src = fetchHex {
        pkg = "phoenix_template";
        version = "${version}";
        sha256 = "eba70070de79b2c3501ef205a74a69f98ab352f3785aa15da9ed161f9fe0fd5d";
      };

      beamDeps = [ phoenix_html ];
    };

    plug = buildMix rec {
      name = "plug";
      version = "1.20.3";

      src = fetchHex {
        pkg = "plug";
        version = "${version}";
        sha256 = "be266aee1b8536ef6409d58cf39a3121319f0ec47cfa1b24024485aa0e76ad76";
      };

      beamDeps = [ mime plug_crypto telemetry ];
    };

    plug_cowboy = buildMix rec {
      name = "plug_cowboy";
      version = "2.9.0";

      src = fetchHex {
        pkg = "plug_cowboy";
        version = "${version}";
        sha256 = "2002bafba4f3a45b55a58e68d70211b153a7ed18d37edb1ceb6e96e7a92c422e";
      };

      beamDeps = [ cowboy cowboy_telemetry plug ];
    };

    plug_crypto = buildMix rec {
      name = "plug_crypto";
      version = "2.2.0";

      src = fetchHex {
        pkg = "plug_crypto";
        version = "${version}";
        sha256 = "83a95744ab1c75876542b6fab135fcc176280e0f301a111c1f757fddcec95d2c";
      };

      beamDeps = [];
    };

    poolboy = buildRebar3 rec {
      name = "poolboy";
      version = "1.5.2";

      src = fetchHex {
        pkg = "poolboy";
        version = "${version}";
        sha256 = "dad79704ce5440f3d5a3681c8590b9dc25d1a561e8f5a9c995281012860901e3";
      };

      beamDeps = [];
    };

    postgrex = buildMix rec {
      name = "postgrex";
      version = "0.22.4";

      src = fetchHex {
        pkg = "postgrex";
        version = "${version}";
        sha256 = "4aae45a2d60e35b04eea2602440be152fae332901f1fc7a60fc7cb7f0f9a9c5a";
      };

      beamDeps = [ db_connection decimal jason ];
    };

    ranch = buildRebar3 rec {
      name = "ranch";
      version = "1.8.1";

      src = fetchHex {
        pkg = "ranch";
        version = "${version}";
        sha256 = "aed58910f4e21deea992a67bf51632b6d60114895eb03bb392bb733064594dd0";
      };

      beamDeps = [];
    };

    req = buildMix rec {
      name = "req";
      version = "0.7.4";

      src = fetchHex {
        pkg = "req";
        version = "${version}";
        sha256 = "4b192d63253e8dcc6221ef992ea9ebef7d3555166e8423aa5b553e86bc3c69a2";
      };

      beamDeps = [ finch jason mime plug ];
    };

    styler = buildMix rec {
      name = "styler";
      version = "1.12.2";

      src = fetchHex {
        pkg = "styler";
        version = "${version}";
        sha256 = "a82baeb6d81e35ee1c4cf8af08e141e8d7872a1d442f6fefce29817869e77a01";
      };

      beamDeps = [];
    };

    swoosh = buildMix rec {
      name = "swoosh";
      version = "1.28.1";

      src = fetchHex {
        pkg = "swoosh";
        version = "${version}";
        sha256 = "d84e08c445f70617afd3a31633db2ea02ceabdfec482bde4b824da63b8150bdc";
      };

      beamDeps = [ bandit cowboy finch idna jason mime plug plug_cowboy req telemetry ];
    };

    tailwind = buildMix rec {
      name = "tailwind";
      version = "0.5.1";

      src = fetchHex {
        pkg = "tailwind";
        version = "${version}";
        sha256 = "c4e26302a59fec72abc5610ecb6ad2116d9aa31f31aab2d4b8eb6e95d25a689c";
      };

      beamDeps = [];
    };

    telemetry = buildRebar3 rec {
      name = "telemetry";
      version = "1.4.2";

      src = fetchHex {
        pkg = "telemetry";
        version = "${version}";
        sha256 = "928f6495066506077862c0d1646609eed891a4326bee3126ba54b60af61febb1";
      };

      beamDeps = [];
    };

    telemetry_metrics = buildMix rec {
      name = "telemetry_metrics";
      version = "1.2.0";

      src = fetchHex {
        pkg = "telemetry_metrics";
        version = "${version}";
        sha256 = "71dde12fc29b58b9c77ec17ec319109e5ca848d010fc1965ed4463bba1837c07";
      };

      beamDeps = [ telemetry ];
    };

    telemetry_poller = buildRebar3 rec {
      name = "telemetry_poller";
      version = "1.3.0";

      src = fetchHex {
        pkg = "telemetry_poller";
        version = "${version}";
        sha256 = "51f18bed7128544a50f75897db9974436ea9bfba560420b646af27a9a9b35211";
      };

      beamDeps = [ telemetry ];
    };

    thousand_island = buildMix rec {
      name = "thousand_island";
      version = "1.5.0";

      src = fetchHex {
        pkg = "thousand_island";
        version = "${version}";
        sha256 = "708923d40523e43cf99041ab37a0d4b0ec426ac6438fa3716ab23d919eaeb412";
      };

      beamDeps = [ telemetry ];
    };

    tzdata = buildMix rec {
      name = "tzdata";
      version = "1.2.2";

      src = fetchHex {
        pkg = "tzdata";
        version = "${version}";
        sha256 = "4a2435eb3614711b220a9f9f9b56204d14518c6a84e94278cc8b697ca62221a7";
      };

      beamDeps = [];
    };

    uxid = buildMix rec {
      name = "uxid";
      version = "0.2.3";

      src = fetchHex {
        pkg = "uxid";
        version = "${version}";
        sha256 = "f64dbae57344892426a38d7becd0b994dcf9540dd5a3ecdcb2cb50fcf9f6cd6b";
      };

      beamDeps = [ ecto ];
    };

    websock = buildMix rec {
      name = "websock";
      version = "0.5.3";

      src = fetchHex {
        pkg = "websock";
        version = "${version}";
        sha256 = "6105453d7fac22c712ad66fab1d45abdf049868f253cf719b625151460b8b453";
      };

      beamDeps = [];
    };

    websock_adapter = buildMix rec {
      name = "websock_adapter";
      version = "0.6.0";

      src = fetchHex {
        pkg = "websock_adapter";
        version = "${version}";
        sha256 = "50021a85bce8f203b086705d9e0c5415e2c7eb05d319111b0428fe71f9934617";
      };

      beamDeps = [ bandit plug plug_cowboy websock ];
    };
  };
in self
