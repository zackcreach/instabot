{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    bandit = buildMix rec {
      name = "bandit";
      version = "1.10.4";

      src = fetchHex {
        pkg = "bandit";
        version = "${version}";
        sha256 = "a5faf501042ac1f31d736d9d4a813b3db4ef812e634583b6a457b0928798a51d";
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

    certifi = buildRebar3 rec {
      name = "certifi";
      version = "2.15.0";

      src = fetchHex {
        pkg = "certifi";
        version = "${version}";
        sha256 = "b147ed22ce71d72eafdad94f055165c1c182f61a2ff49df28bcc71d1d5b94a60";
      };

      beamDeps = [];
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
      version = "2.14.2";

      src = fetchHex {
        pkg = "cowboy";
        version = "${version}";
        sha256 = "569081da046e7b41b5df36aa359be71a0c8874e5b9cff6f747073fc57baf1ab9";
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
      version = "2.16.0";

      src = fetchHex {
        pkg = "cowlib";
        version = "${version}";
        sha256 = "7f478d80d66b747344f0ea7708c187645cfcc08b11aa424632f78e25bf05db51";
      };

      beamDeps = [];
    };

    db_connection = buildMix rec {
      name = "db_connection";
      version = "2.9.0";

      src = fetchHex {
        pkg = "db_connection";
        version = "${version}";
        sha256 = "17d502eacaf61829db98facf6f20808ed33da6ccf495354a41e64fe42f9c509c";
      };

      beamDeps = [ telemetry ];
    };

    decimal = buildMix rec {
      name = "decimal";
      version = "2.3.0";

      src = fetchHex {
        pkg = "decimal";
        version = "${version}";
        sha256 = "a4d66355cb29cb47c3cf30e71329e58361cfcb37c34235ef3bf1d7bf3773aeac";
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
      version = "3.13.5";

      src = fetchHex {
        pkg = "ecto";
        version = "${version}";
        sha256 = "df9efebf70cf94142739ba357499661ef5dbb559ef902b68ea1f3c1fabce36de";
      };

      beamDeps = [ decimal jason telemetry ];
    };

    ecto_sql = buildMix rec {
      name = "ecto_sql";
      version = "3.13.5";

      src = fetchHex {
        pkg = "ecto_sql";
        version = "${version}";
        sha256 = "aa36751f4e6a2b56ae79efb0e088042e010ff4935fc8684e74c23b1f49e25fdc";
      };

      beamDeps = [ db_connection ecto postgrex telemetry ];
    };

    elixir_make = buildMix rec {
      name = "elixir_make";
      version = "0.9.0";

      src = fetchHex {
        pkg = "elixir_make";
        version = "${version}";
        sha256 = "db23d4fd8b757462ad02f8aa73431a426fe6671c80b200d9710caf3d1dd0ffdb";
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
      version = "0.21.0";

      src = fetchHex {
        pkg = "finch";
        version = "${version}";
        sha256 = "87dc6e169794cb2570f75841a19da99cfde834249568f2a5b121b809588a4377";
      };

      beamDeps = [ mime mint nimble_options nimble_pool telemetry ];
    };

    fine = buildMix rec {
      name = "fine";
      version = "0.1.4";

      src = fetchHex {
        pkg = "fine";
        version = "${version}";
        sha256 = "be3324cc454a42d80951cf6023b9954e9ff27c6daa255483b3e8d608670303f5";
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

    hackney = buildRebar3 rec {
      name = "hackney";
      version = "1.25.0";

      src = fetchHex {
        pkg = "hackney";
        version = "${version}";
        sha256 = "7209bfd75fd1f42467211ff8f59ea74d6f2a9e81cbcee95a56711ee79fd6b1d4";
      };

      beamDeps = [ certifi idna metrics mimerl parse_trans ssl_verify_fun unicode_util_compat ];
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
      version = "1.0.3";

      src = fetchHex {
        pkg = "hpax";
        version = "${version}";
        sha256 = "8eab6e1cfa8d5918c2ce4ba43588e894af35dbd8e91e6e55c817bca5847df34a";
      };

      beamDeps = [];
    };

    idna = buildRebar3 rec {
      name = "idna";
      version = "6.1.1";

      src = fetchHex {
        pkg = "idna";
        version = "${version}";
        sha256 = "92376eb7894412ed19ac475e4a86f7b413c1b9fbb5bd16dccd57934157944cea";
      };

      beamDeps = [ unicode_util_compat ];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.4";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b";
      };

      beamDeps = [ decimal ];
    };

    lazy_html = buildMix rec {
      name = "lazy_html";
      version = "0.1.10";

      src = fetchHex {
        pkg = "lazy_html";
        version = "${version}";
        sha256 = "50f67e5faa09d45a99c1ddf3fac004f051997877dc8974c5797bb5ccd8e27058";
      };

      beamDeps = [ cc_precompiler elixir_make fine ];
    };

    metrics = buildRebar3 rec {
      name = "metrics";
      version = "1.0.1";

      src = fetchHex {
        pkg = "metrics";
        version = "${version}";
        sha256 = "69b09adddc4f74a40716ae54d140f93beb0fb8978d8636eaded0c31b6f099f16";
      };

      beamDeps = [];
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

    mimerl = buildRebar3 rec {
      name = "mimerl";
      version = "1.5.0";

      src = fetchHex {
        pkg = "mimerl";
        version = "${version}";
        sha256 = "db648ce065bae14ea84ca8b5dd123f42f49417cef693541110bf6f9e9be9ecc4";
      };

      beamDeps = [];
    };

    mint = buildMix rec {
      name = "mint";
      version = "1.7.1";

      src = fetchHex {
        pkg = "mint";
        version = "${version}";
        sha256 = "fceba0a4d0f24301ddee3024ae116df1c3f4bb7a563a731f45fdfeb9d39a231b";
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
      version = "2.21.1";

      src = fetchHex {
        pkg = "oban";
        version = "${version}";
        sha256 = "8162a160924cf4a25905fed2a9242e7787d88e320e3b5b0dcf324eb17c51c4e6";
      };

      beamDeps = [ ecto_sql jason postgrex telemetry ];
    };

    parse_trans = buildRebar3 rec {
      name = "parse_trans";
      version = "3.4.1";

      src = fetchHex {
        pkg = "parse_trans";
        version = "${version}";
        sha256 = "620a406ce75dada827b82e453c19cf06776be266f5a67cff34e1ef2cbb60e49a";
      };

      beamDeps = [];
    };

    phoenix = buildMix rec {
      name = "phoenix";
      version = "1.8.5";

      src = fetchHex {
        pkg = "phoenix";
        version = "${version}";
        sha256 = "83b2bb125127e02e9f475c8e3e92736325b5b01b0b9b05407bcb4083b7a32485";
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
      version = "1.6.2";

      src = fetchHex {
        pkg = "phoenix_live_reload";
        version = "${version}";
        sha256 = "d1f89c18114c50d394721365ffb428cce24f1c13de0467ffa773e2ff4a30d5b9";
      };

      beamDeps = [ file_system phoenix ];
    };

    phoenix_live_view = buildMix rec {
      name = "phoenix_live_view";
      version = "1.1.27";

      src = fetchHex {
        pkg = "phoenix_live_view";
        version = "${version}";
        sha256 = "415735d0b2c612c9104108b35654e977626a0cb346711e1e4f1ed16e3c827ede";
      };

      beamDeps = [ jason lazy_html phoenix phoenix_html phoenix_template plug telemetry ];
    };

    phoenix_pubsub = buildMix rec {
      name = "phoenix_pubsub";
      version = "2.2.0";

      src = fetchHex {
        pkg = "phoenix_pubsub";
        version = "${version}";
        sha256 = "adc313a5bf7136039f63cfd9668fde73bba0765e0614cba80c06ac9460ff3e96";
      };

      beamDeps = [];
    };

    phoenix_template = buildMix rec {
      name = "phoenix_template";
      version = "1.0.4";

      src = fetchHex {
        pkg = "phoenix_template";
        version = "${version}";
        sha256 = "2c0c81f0e5c6753faf5cca2f229c9709919aba34fab866d3bc05060c9c444206";
      };

      beamDeps = [ phoenix_html ];
    };

    plug = buildMix rec {
      name = "plug";
      version = "1.19.1";

      src = fetchHex {
        pkg = "plug";
        version = "${version}";
        sha256 = "560a0017a8f6d5d30146916862aaf9300b7280063651dd7e532b8be168511e62";
      };

      beamDeps = [ mime plug_crypto telemetry ];
    };

    plug_cowboy = buildMix rec {
      name = "plug_cowboy";
      version = "2.8.0";

      src = fetchHex {
        pkg = "plug_cowboy";
        version = "${version}";
        sha256 = "9cbfaaf17463334ca31aed38ea7e08a68ee37cabc077b1e9be6d2fb68e0171d0";
      };

      beamDeps = [ cowboy cowboy_telemetry plug ];
    };

    plug_crypto = buildMix rec {
      name = "plug_crypto";
      version = "2.1.1";

      src = fetchHex {
        pkg = "plug_crypto";
        version = "${version}";
        sha256 = "6470bce6ffe41c8bd497612ffde1a7e4af67f36a15eea5f921af71cf3e11247c";
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
      version = "0.22.0";

      src = fetchHex {
        pkg = "postgrex";
        version = "${version}";
        sha256 = "a68c4261e299597909e03e6f8ff5a13876f5caadaddd0d23af0d0a61afcc5d84";
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
      version = "0.5.17";

      src = fetchHex {
        pkg = "req";
        version = "${version}";
        sha256 = "0b8bc6ffdfebbc07968e59d3ff96d52f2202d0536f10fef4dc11dc02a2a43e39";
      };

      beamDeps = [ finch jason mime plug ];
    };

    ssl_verify_fun = buildRebar3 rec {
      name = "ssl_verify_fun";
      version = "1.1.7";

      src = fetchHex {
        pkg = "ssl_verify_fun";
        version = "${version}";
        sha256 = "fe4c190e8f37401d30167c8c405eda19469f34577987c76dde613e838bbc67f8";
      };

      beamDeps = [];
    };

    styler = buildMix rec {
      name = "styler";
      version = "1.11.0";

      src = fetchHex {
        pkg = "styler";
        version = "${version}";
        sha256 = "70f36165d0cf238a32b7a456fdef6a9c72e77e657d7ac4a0ace33aeba3f2b8c0";
      };

      beamDeps = [];
    };

    swoosh = buildMix rec {
      name = "swoosh";
      version = "1.24.0";

      src = fetchHex {
        pkg = "swoosh";
        version = "${version}";
        sha256 = "6ddd84550800468d0e2c15a8aaff924a64c014ed6cff90318077efd1672b8b3b";
      };

      beamDeps = [ bandit cowboy finch hackney idna jason mime plug plug_cowboy req telemetry ];
    };

    tailwind = buildMix rec {
      name = "tailwind";
      version = "0.4.1";

      src = fetchHex {
        pkg = "tailwind";
        version = "${version}";
        sha256 = "6249d4f9819052911120dbdbe9e532e6bd64ea23476056adb7f730aa25c220d1";
      };

      beamDeps = [];
    };

    telemetry = buildRebar3 rec {
      name = "telemetry";
      version = "1.4.1";

      src = fetchHex {
        pkg = "telemetry";
        version = "${version}";
        sha256 = "2172e05a27531d3d31dd9782841065c50dd5c3c7699d95266b2edd54c2dafa1c";
      };

      beamDeps = [];
    };

    telemetry_metrics = buildMix rec {
      name = "telemetry_metrics";
      version = "1.1.0";

      src = fetchHex {
        pkg = "telemetry_metrics";
        version = "${version}";
        sha256 = "e7b79e8ddfde70adb6db8a6623d1778ec66401f366e9a8f5dd0955c56bc8ce67";
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
      version = "1.4.3";

      src = fetchHex {
        pkg = "thousand_island";
        version = "${version}";
        sha256 = "6e4ce09b0fd761a58594d02814d40f77daff460c48a7354a15ab353bb998ea0b";
      };

      beamDeps = [ telemetry ];
    };

    tzdata = buildMix rec {
      name = "tzdata";
      version = "1.1.3";

      src = fetchHex {
        pkg = "tzdata";
        version = "${version}";
        sha256 = "d4ca85575a064d29d4e94253ee95912edfb165938743dbf002acdf0dcecb0c28";
      };

      beamDeps = [ hackney ];
    };

    unicode_util_compat = buildRebar3 rec {
      name = "unicode_util_compat";
      version = "0.7.1";

      src = fetchHex {
        pkg = "unicode_util_compat";
        version = "${version}";
        sha256 = "b3a917854ce3ae233619744ad1e0102e05673136776fb2fa76234f3e03b23642";
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
      version = "0.5.9";

      src = fetchHex {
        pkg = "websock_adapter";
        version = "${version}";
        sha256 = "5534d5c9adad3c18a0f58a9371220d75a803bf0b9a3d87e6fe072faaeed76a08";
      };

      beamDeps = [ bandit plug plug_cowboy websock ];
    };
  };
in self
