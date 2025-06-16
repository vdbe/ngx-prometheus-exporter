{
  testers,
}:

testers.runNixOSTest {
  name = "nginx-prometheus-exporter";

  nodes.machine =
    {
      config,
      pkgs,
      lib,
      ...
    }:

    let
      ngxPrometheusExporter = pkgs.callPackage ../package.nix { nginx = config.services.nginx.package; };
      ngxPrometheusExporterModule = "${lib.getLib ngxPrometheusExporter}/lib/libngx_prometheus_exporter.so";
    in
    {
      services.nginx = {
        enable = true;
        prependConfig = ''
          load_module "${ngxPrometheusExporterModule}";
        '';

        virtualHosts = {
          "localhost" = {
            locations = {
              "/metrics" = {
                extraConfig = ''
                  prometheus_exporter on;
                '';
              };
            };
          };
        };
      };
    };

  interactive.sshBackdoor.enable = true;
  testScript = ''
    # import tempfile
    # from pathlib import Path
    # import sys

    url = "http://localhost/metrics"

    def check_code(method: str, code: str, extra_args: str = ""):
      http_code = machine.succeed(
        f"curl -w '%{{http_code}}' --head -X {method} {extra_args} {url}"
      )
      assert http_code.split("\n")[-1] == code

    def check_length():
      # with tempfile.NamedTemporaryFile(delete_on_close=False) as fd:
      #   fd.write(b"Hello, World!")
      #   fd.flush()
      #   name = fd.name;
      #   fd.close()
      #   header_content_length = machine.succeed(
      #     f"curl -N  --create-dirs -w '%header{{Content-Length}}' {url} --fail -o {name}"
      #   )
      #   print(f"header content length: {header_content_length}", file=sys.stderr)
      #   file_size = Path(f"{name}").stat().st_size
      #   print(f"file_size: {file_size}", file=sys.stderr)
      #   with open(name, 'r') as f:
      #     print(f.read(), file=sys.stderr)
      #   assert header_content_length == f"{file_size}"

      # Not pretty but it works
      resp = machine.succeed(
        f"curl  -w '%header{{Content-Length}}' {url} --fail"
      )
      length = resp.split("\n")[-1]
      body = resp.rstrip(length)
      assert length == f"{len(body)}"

    start_all()

    with subtest("Wait for startup"):
      machine.wait_for_unit("multi-user.target")

    with subtest("Wait for nginx"):
      machine.wait_for_unit("nginx")
      machine.wait_for_open_port(80)

    with subtest("Check status codes"):
      check_code("HEAD", "200", "--fail")
      check_code("GET", "200", "--fail")
      check_code("POST", "405")

    with subtest("Check length"):
      for _ in range(100):
        check_length()

    # TODO: Compare stats with stub_status
  '';
}
