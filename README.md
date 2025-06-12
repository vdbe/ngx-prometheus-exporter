# ngx-prometheus-exporter

Nginx prometheus exporter as a stub_status like module.

## nginx config

```nginx.conf
load_module "/.../libngx_prometheus_exporter.so";
# ...
http {
    # ...
    server {
        # ...
        location /metrics {
            allow 127.0.0.1;
            allow ::1;
            deny all;

            access_log off;
            prometheus_exporter on;
        }
    }
}
```
