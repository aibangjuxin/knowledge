#!/usr/bin/env python3
"""
Nginx配置生成器 - 根据迁移配置生成Nginx配置文件
Nginx Configuration Generator - Generates Nginx config based on migration settings
"""

import os
import logging
from typing import Dict, List
from jinja2 import Template

logger = logging.getLogger(__name__)


class NginxConfigGenerator:
    """Nginx配置生成器"""
    
    def __init__(self, template_path: str = None):
        """
        初始化配置生成器
        
        Args:
            template_path: Nginx配置模板文件路径
        """
        self.template_path = template_path
        self.nginx_template = self._get_nginx_template()
    
    def _get_nginx_template(self) -> Template:
        """获取Nginx配置模板"""
        if self.template_path and os.path.exists(self.template_path):
            with open(self.template_path, 'r', encoding='utf-8') as f:
                template_content = f.read()
        else:
            # 使用内置模板
            template_content = self._get_default_template()
        
        return Template(template_content)
    
    def _get_default_template(self) -> str:
        """获取默认Nginx配置模板"""
        return """
# Nginx配置文件 - 自动生成
# Generated Nginx configuration for K8s cluster migration

# 上游服务器配置
{% for service in services %}
# {{ service.name }} 服务配置
upstream {{ service.name }}_old_backend {
    server {{ service.old_backend }};
    keepalive 32;
}

upstream {{ service.name }}_new_backend {
    server {{ service.new_backend }};
    keepalive 32;
}
{% endfor %}

# Lua脚本用于流量分配
lua_package_path "/etc/nginx/lua/?.lua;;";
init_by_lua_block {
    -- 初始化随机种子
    math.randomseed(ngx.time())
}

# 服务器配置
{% for service in services %}
server {
    listen 80;
    server_name {{ service.old_host }};
    
    # 健康检查端点
    location /nginx-health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
    
    # 主要路由逻辑
    location / {
        # 设置代理头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # 连接和超时设置
        proxy_connect_timeout {{ global.default_timeout | default('30s') }};
        proxy_send_timeout {{ global.default_timeout | default('30s') }};
        proxy_read_timeout {{ global.default_timeout | default('30s') }};
        
        # 重试设置
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_next_upstream_tries {{ global.retry_attempts | default(3) }};
        
        {% if service.migration_enabled %}
        # 流量分配逻辑
        access_by_lua_block {
            local target_backend = "{{ service.name }}_old_backend"
            
            {% if service.strategy == 'weight' %}
            -- 基于权重的分配
            local percentage = {{ service.percentage }}
            if percentage > 0 then
                local random_value = math.random(0, 99)
                if random_value < percentage then
                    target_backend = "{{ service.name }}_new_backend"
                end
            end
            {% endif %}
            
            {% for rule in service.header_rules %}
            -- 基于请求头的路由
            local header_value = ngx.var.http_{{ rule.header | replace('-', '_') | lower }}
            if header_value == "{{ rule.value }}" then
                {% if rule.target == 'new_cluster' %}
                target_backend = "{{ service.name }}_new_backend"
                {% else %}
                target_backend = "{{ service.name }}_old_backend"
                {% endif %}
            end
            {% endfor %}
            
            {% for rule in service.ip_rules %}
            -- 基于IP的路由
            local client_ip = ngx.var.remote_addr
            -- 简化的IP范围检查（生产环境需要更完善的实现）
            if string.match(client_ip, "^{{ rule.cidr | replace('/', '%.') | replace('0', '') }}") then
                {% if rule.target == 'new_cluster' %}
                target_backend = "{{ service.name }}_new_backend"
                {% else %}
                target_backend = "{{ service.name }}_old_backend"
                {% endif %}
            end
            {% endfor %}
            
            -- 设置上游后端
            ngx.var.target_backend = target_backend
        }
        
        # 动态代理到选定的后端
        proxy_pass http://$target_backend;
        {% else %}
        # 迁移未启用，直接代理到旧集群
        proxy_pass http://{{ service.name }}_old_backend;
        {% endif %}
    }
    
    # 错误页面
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}

{% if service.new_protocol == 'https' %}
# HTTPS服务器配置（如果新集群使用HTTPS）
server {
    listen 443 ssl;
    server_name {{ service.old_host }};
    
    # SSL配置（需要根据实际情况配置证书）
    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    
    # 其他配置与HTTP服务器相同
    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        {% if service.migration_enabled %}
        # 同样的流量分配逻辑
        access_by_lua_block {
            -- 流量分配逻辑（与HTTP相同）
            local target_backend = "{{ service.name }}_old_backend"
            local percentage = {{ service.percentage }}
            if percentage > 0 then
                local random_value = math.random(0, 99)
                if random_value < percentage then
                    target_backend = "{{ service.name }}_new_backend"
                end
            end
            ngx.var.target_backend = target_backend
        }
        
        proxy_pass https://$target_backend;
        {% else %}
        proxy_pass http://{{ service.name }}_old_backend;
        {% endif %}
    }
}
{% endif %}
{% endfor %}

# 全局配置
worker_processes auto;
worker_connections 1024;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # 基本设置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # 日志格式
    log_format migration_log '$remote_addr - $remote_user [$time_local] '
                            '"$request" $status $body_bytes_sent '
                            '"$http_referer" "$http_user_agent" '
                            'backend="$target_backend" '
                            'upstream_response_time=$upstream_response_time '
                            'request_time=$request_time';
    
    # 访问日志
    access_log /var/log/nginx/migration_access.log migration_log;
    error_log /var/log/nginx/migration_error.log;
    
    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # 包含服务器配置
    include /etc/nginx/conf.d/*.conf;
}
"""
    
    def generate_config(self, migration_config: Dict) -> str:
        """
        生成Nginx配置
        
        Args:
            migration_config: 迁移配置字典
            
        Returns:
            str: 生成的Nginx配置内容
        """
        try:
            # 准备模板变量
            template_vars = {
                'services': [],
                'global': migration_config.get('global', {})
            }
            
            # 处理服务配置
            for service_config in migration_config.get('services', []):
                # 处理migration配置，支持两种格式
                migration_config_data = service_config.get('migration', {})
                if isinstance(migration_config_data, dict):
                    migration_enabled = migration_config_data.get('enabled', False)
                    strategy = migration_config_data.get('strategy', 'weight')
                    percentage = migration_config_data.get('percentage', 0)
                else:
                    # 兼容直接在service级别的配置
                    migration_enabled = service_config.get('migration_enabled', False)
                    strategy = service_config.get('strategy', 'weight')
                    percentage = service_config.get('percentage', 0)
                
                service_vars = {
                    'name': service_config['name'],
                    'old_host': service_config['old_host'],
                    'old_backend': service_config['old_backend'],
                    'old_protocol': service_config['old_protocol'],
                    'new_host': service_config['new_host'],
                    'new_backend': service_config['new_backend'],
                    'new_protocol': service_config['new_protocol'],
                    'migration_enabled': migration_enabled,
                    'strategy': strategy,
                    'percentage': percentage,
                    'header_rules': service_config.get('canary', {}).get('header_rules', service_config.get('header_rules', [])),
                    'ip_rules': service_config.get('canary', {}).get('ip_rules', service_config.get('ip_rules', [])),
                    'user_rules': service_config.get('canary', {}).get('user_rules', service_config.get('user_rules', []))
                }
                
                template_vars['services'].append(service_vars)
            
            # 渲染模板
            config_content = self.nginx_template.render(**template_vars)
            
            logger.info("Nginx configuration generated successfully")
            return config_content
            
        except Exception as e:
            logger.error(f"Error generating Nginx configuration: {e}")
            raise
    
    def save_config(self, config_content: str, output_path: str) -> bool:
        """
        保存配置到文件
        
        Args:
            config_content: 配置内容
            output_path: 输出文件路径
            
        Returns:
            bool: 是否保存成功
        """
        try:
            # 确保目录存在
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            
            # 写入配置文件
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(config_content)
            
            logger.info(f"Nginx configuration saved to: {output_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error saving Nginx configuration: {e}")
            return False
    
    def validate_nginx_config(self, config_path: str) -> tuple[bool, str]:
        """
        验证Nginx配置文件语法
        
        Args:
            config_path: 配置文件路径
            
        Returns:
            tuple[bool, str]: (是否有效, 错误信息)
        """
        try:
            import subprocess
            
            # 使用nginx -t命令验证配置
            result = subprocess.run(
                ['nginx', '-t', '-c', config_path],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                return True, "Configuration is valid"
            else:
                return False, result.stderr
                
        except FileNotFoundError:
            return False, "nginx command not found"
        except Exception as e:
            return False, f"Error validating configuration: {str(e)}"
    
    def reload_nginx_config(self) -> bool:
        """
        重新加载Nginx配置
        
        Returns:
            bool: 是否重新加载成功
        """
        try:
            import subprocess
            
            # 发送HUP信号重新加载配置
            result = subprocess.run(['nginx', '-s', 'reload'], capture_output=True, text=True)
            
            if result.returncode == 0:
                logger.info("Nginx configuration reloaded successfully")
                return True
            else:
                logger.error(f"Error reloading Nginx: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error reloading Nginx configuration: {e}")
            return False


# 示例使用
if __name__ == "__main__":
    # 示例配置
    migration_config = {
        'global': {
            'default_timeout': '30s',
            'retry_attempts': 3,
            'health_check_interval': '30s'
        },
        'services': [
            {
                'name': 'api-name01',
                'old_host': 'api-name01.teamname.dev.aliyun.intracloud.cn.aibang',
                'old_backend': 'bbdm-api.aibang-1111111111-bbdm.svc.cluster.local:8078',
                'old_protocol': 'http',
                'new_host': 'api-name01.kong.dev.aliyun.intracloud.cn.aibang',
                'new_backend': 'api-name01.kong.dev.aliyun.intracloud.cn.aibang:443',
                'new_protocol': 'https',
                'migration': {
                    'enabled': True,
                    'strategy': 'weight',
                    'percentage': 20
                },
                'canary': {
                    'header_rules': [
                        {'header': 'X-Migration-Target', 'value': 'new', 'target': 'new_cluster'}
                    ],
                    'ip_rules': [
                        {'cidr': '10.0.0.0/8', 'target': 'new_cluster'}
                    ],
                    'user_rules': []
                }
            }
        ]
    }
    
    # 创建配置生成器
    generator = NginxConfigGenerator()
    
    # 生成配置
    config_content = generator.generate_config(migration_config)
    
    # 保存配置
    output_path = "/tmp/nginx_migration.conf"
    generator.save_config(config_content, output_path)
    
    print(f"Nginx configuration generated and saved to: {output_path}")
    print("\nGenerated configuration preview:")
    print(config_content[:1000] + "..." if len(config_content) > 1000 else config_content)