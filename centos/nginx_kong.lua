return [[
charset UTF-8;

> if anonymous_reports then
${{SYSLOG_REPORTS}}
> end

error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

> if nginx_optimizations then
>-- send_timeout 60s;          # default value
>-- keepalive_timeout 75s;     # default value
>-- client_body_timeout 60s;   # default value
>-- client_header_timeout 60s; # default value
>-- tcp_nopush on;             # disabled until benchmarked
>-- proxy_buffer_size 128k;    # disabled until benchmarked
>-- proxy_buffers 4 256k;      # disabled until benchmarked
>-- proxy_busy_buffers_size 256k; # disabled until benchmarked
>-- reset_timedout_connection on; # disabled until benchmarked
> end

client_max_body_size ${{CLIENT_MAX_BODY_SIZE}};
proxy_ssl_server_name on;
underscores_in_headers on;

lua_package_path '${{LUA_PACKAGE_PATH}};;';
lua_package_cpath '${{LUA_PACKAGE_CPATH}};;';
lua_socket_pool_size ${{LUA_SOCKET_POOL_SIZE}};
lua_max_running_timers 4096;
lua_max_pending_timers 16384;
lua_shared_dict kong                5m;
lua_shared_dict kong_cache          ${{MEM_CACHE_SIZE}};
lua_shared_dict kong_process_events 5m;
lua_shared_dict kong_cluster_events 5m;
> if database == "cassandra" then
lua_shared_dict kong_cassandra      5m;
> end
lua_socket_log_errors off;
> if lua_ssl_trusted_certificate then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE}}';
lua_ssl_verify_depth ${{LUA_SSL_VERIFY_DEPTH}};
> end

lua_shared_dict kong_prometheus_metrics 10M;

init_by_lua_block {
    kong = require 'kong'
    kong.init()
    prometheus = require("prometheus").init("kong_prometheus_metrics", "kong_")
    metric_http_requests_total = prometheus:counter("http_requests_total", "Number of HTTP requests", {"host", "api", "status"})
    metric_http_request_duration_ms = prometheus:histogram("http_request_duration_ms", "HTTP request latency", {"host", "api"})
    metric_connections = prometheus:gauge("http_connections", "Number of HTTP connections", {"state"})
    metric_http_request_size_bytes = prometheus:histogram("http_request_size_bytes","Size of HTTP request",{"host","api"},{10,100,1000,10000,100000,1000000});
    metric_http_response_size_bytes = prometheus:histogram("http_response_size_bytes","Size of HTTP responses",{"host","api"},{10,100,1000,10000,100000,1000000});
    metric_http_upstream_duration_ms = prometheus:histogram("http_upstream_duration_ms","upstream duration ms",{"host","api"});
    metric_http_kong_duration_ms = prometheus:histogram("http_kong_duration_ms","kong duration ms",{"host","api"});
    
}
log_by_lua '
  local host = ngx.var.host:gsub("^www.", "")
  metric_http_requests_total:inc(1, {host, ngx.var.uri, ngx.var.status})
';
init_worker_by_lua_block {
    kong.init_worker()
}


proxy_next_upstream_tries 999;

upstream kong_upstream {
    server 0.0.0.1;
    balancer_by_lua_block {
        kong.balancer()
    }
    keepalive ${{UPSTREAM_KEEPALIVE}};
}

server {
    server_name kong;
    listen ${{PROXY_LISTEN}}${{PROXY_PROTOCOL}};
    error_page 400 404 408 411 412 413 414 417 /kong_error_handler;
    error_page 500 502 503 504 /kong_error_handler;

    access_log ${{PROXY_ACCESS_LOG}};
    error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

    client_body_buffer_size ${{CLIENT_BODY_BUFFER_SIZE}};

> if ssl then
    listen ${{PROXY_LISTEN_SSL}} ssl${{HTTP2}}${{PROXY_PROTOCOL}};
    ssl_certificate ${{SSL_CERT}};
    ssl_certificate_key ${{SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_certificate_by_lua_block {
        kong.ssl_certificate()
    }

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ${{SSL_CIPHERS}};
> end

> if client_ssl then
    proxy_ssl_certificate ${{CLIENT_SSL_CERT}};
    proxy_ssl_certificate_key ${{CLIENT_SSL_CERT_KEY}};
> end

    real_ip_header     ${{REAL_IP_HEADER}};
    real_ip_recursive  ${{REAL_IP_RECURSIVE}};
> for i = 1, #trusted_ips do
    set_real_ip_from   $(trusted_ips[i]);
> end

    location / {
        set $upstream_host               '';
        set $upstream_upgrade            '';
        set $upstream_connection         '';
        set $upstream_scheme             '';
        set $upstream_uri                '';
        set $upstream_x_forwarded_for    '';
        set $upstream_x_forwarded_proto  '';
        set $upstream_x_forwarded_host   '';
        set $upstream_x_forwarded_port   '';

        rewrite_by_lua_block {
            kong.rewrite()
        }

        access_by_lua_block {
            kong.access()
        }

        proxy_http_version 1.1;
        proxy_set_header   Host              $upstream_host;
        proxy_set_header   Upgrade           $upstream_upgrade;
        proxy_set_header   Connection        $upstream_connection;
        proxy_set_header   X-Forwarded-For   $upstream_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $upstream_x_forwarded_proto;
        proxy_set_header   X-Forwarded-Host  $upstream_x_forwarded_host;
        proxy_set_header   X-Forwarded-Port  $upstream_x_forwarded_port;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_pass_header  Server;
        proxy_pass_header  Date;
        proxy_ssl_name     $upstream_host;
        proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;

        header_filter_by_lua_block {
            kong.header_filter()
        }

        body_filter_by_lua_block {
            kong.body_filter()
        }

        log_by_lua_block {
            local basic_serializer = require "kong.plugins.log-serializers.basic"
            kong.log()
            local message = basic_serializer.serialize(ngx)
            local apiname = string.gsub(message.api.name, "%.", "_")
            local host = ngx.var.host:gsub("^www.", "")
            metric_http_request_duration_ms:observe(message.latencies.request, {host, apiname})
            metric_http_requests_total:inc(1,{host, apiname, message.response.status})
            metric_http_request_size_bytes:observe(message.request.size, {host, apiname})
            metric_http_response_size_bytes:observe(message.response.size, {host, apiname})
            metric_http_upstream_duration_ms:observe(message.latencies.proxy, {host, apiname})
            metric_http_kong_duration_ms:observe(message.latencies.kong, {host, apiname})
        }
    }

    location = /kong_error_handler {
        internal;
        content_by_lua_block {
            kong.handle_error()
        }
    }
}

server {
    server_name kong_admin;
    listen ${{ADMIN_LISTEN}};

    access_log ${{ADMIN_ACCESS_LOG}};
    error_log ${{ADMIN_ERROR_LOG}} ${{LOG_LEVEL}};

    client_max_body_size 10m;
    client_body_buffer_size 10m;

> if admin_ssl then
    listen ${{ADMIN_LISTEN_SSL}} ssl${{ADMIN_HTTP2}};
    ssl_certificate ${{ADMIN_SSL_CERT}};
    ssl_certificate_key ${{ADMIN_SSL_CERT_KEY}};
    ssl_protocols TLSv1.1 TLSv1.2;

    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ${{SSL_CIPHERS}};
> end

    location / {
        default_type application/json;
        content_by_lua_block {
            kong.serve_admin_api()
        }
    }

    location /nginx_status {
        internal;
        access_log off;
        stub_status;
    }

    location /robots.txt {
        return 200 'User-agent: *\nDisallow: /';
    }
}
]]
