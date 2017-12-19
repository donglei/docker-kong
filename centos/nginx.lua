> if nginx_user then
user ${{NGINX_USER}};
> end
worker_processes ${{NGINX_WORKER_PROCESSES}};
daemon ${{NGINX_DAEMON}};

pid pids/nginx.pid;
error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};

> if nginx_optimizations then
worker_rlimit_nofile ${{WORKER_RLIMIT}};
> end

events {
> if nginx_optimizations then
    worker_connections ${{WORKER_CONNECTIONS}};
    multi_accept on;
> end
}


http {
    include 'nginx-kong.conf';

    server {
	  listen 9145;
	  allow 10.0.0.0/8;
	  deny all;
	  location /metrics {
	    content_by_lua '
	      metric_connections:set(ngx.var.connections_reading, {"reading"})
	      metric_connections:set(ngx.var.connections_waiting, {"waiting"})
	      metric_connections:set(ngx.var.connections_writing, {"writing"})
	      prometheus:collect()
	    ';
  	   }
	}
}
