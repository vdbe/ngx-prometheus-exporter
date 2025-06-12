# ngx-prometheus-exporter

## nginx config

```nginx.conf
load_module "/.../libngx_prometheus_exporter.so";
# ...
http {
    # ...
    server {
        # ...
        location /metrics {
            prometheus_exporter true;
            access_log off;
            allow 127.0.0.1;
            allow ::1;
            deny all;
        }
    }
}

```
