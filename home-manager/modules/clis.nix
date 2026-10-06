{ pkgs, brevSource, ... }:

let
  brev = pkgs.buildGoModule {
    pname = "brev";
    version = "dev-${brevSource.shortRev}";
    src = brevSource;
    vendorHash = "sha256-+FkH1wvNkwH/DW+CRCn0Cbjr+DgMugJjs94A1aEU0i0=";
    subPackages = [ "." ];
    ldflags = [
      "-X github.com/brevdev/brev-cli/pkg/cmd/version.Version=dev-${brevSource.shortRev}"
    ];
    postInstall = ''
      mv "$out/bin/brev-cli" "$out/bin/brev"
    '';
    doCheck = false;
  };
in {
  # This path takes precedence over a previously installed vendor binary.
  # Home Manager backs up an existing regular file during make apply.
  home.file.".local/bin/brev".source = "${brev}/bin/brev";
}
