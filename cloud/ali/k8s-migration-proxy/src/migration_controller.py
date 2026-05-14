#!/usr/bin/env python3
"""
迁移控制器 - 整合配置管理、流量分配和Nginx配置生成
Migration Controller - Integrates config management, traffic allocation, and Nginx config generation
"""

import os
import time
import logging
import signal
import sys
from typing import Dict, Optional
from config_manager import ConfigManager
from traffic_allocator import TrafficAllocator
from nginx_config_generator import NginxConfigGenerator

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MigrationController:
    """迁移控制器 - 协调所有组件"""
    
    def __init__(self, 
                 namespace: str = "aibang-1111111111-bbdm",
                 configmap_name: str = "migration-config",
                 config_key: str = "migration.yaml",
                 nginx_config_path: str = "/etc/nginx/conf.d/migration.conf",
                 local_config_path: Optional[str] = None):
        """
        初始化迁移控制器
        
        Args:
            namespace: K8s命名空间
            configmap_name: ConfigMap名称
            config_key: ConfigMap中的配置键
            nginx_config_path: Nginx配置文件输出路径
            local_config_path: 本地配置文件路径（开发环境）
        """
        self.namespace = namespace
        self.configmap_name = configmap_name
        self.config_key = config_key
        self.nginx_config_path = nginx_config_path
        self.local_config_path = local_config_path
        
        # 初始化组件
        self.config_manager = ConfigManager(
            namespace=namespace,
            configmap_name=configmap_name,
            config_key=config_key,
            local_config_path=local_config_path
        )
        
        self.traffic_allocator = TrafficAllocator()
        self.nginx_generator = NginxConfigGenerator()
        
        # 运行状态
        self.running = False
        self.last_config_hash = ""
        
        # 注册配置变更回调
        self.config_manager.add_config_callback(self._on_config_change)
        
        # 注册信号处理器
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """信号处理器"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.stop()
    
    def _on_config_change(self, new_config: Dict):
        """配置变更回调"""
        logger.info("Configuration changed, updating components...")
        
        try:
            # 验证新配置
            is_valid, message = self.config_manager.validate_config(new_config)
            if not is_valid:
                logger.error(f"Invalid configuration: {message}")
                return
            
            # 更新流量分配器
            self.traffic_allocator.load_config(new_config)
            logger.info("Traffic allocator updated")
            
            # 生成新的Nginx配置
            self._update_nginx_config(new_config)
            
            # 记录配置哈希
            import hashlib
            import json
            config_str = json.dumps(new_config, sort_keys=True)
            self.last_config_hash = hashlib.md5(config_str.encode()).hexdigest()
            
            logger.info("Configuration update completed successfully")
            
        except Exception as e:
            logger.error(f"Error updating configuration: {e}")
    
    def _update_nginx_config(self, config: Dict):
        """更新Nginx配置"""
        try:
            # 生成新的Nginx配置
            nginx_config = self.nginx_generator.generate_config(config)
            
            # 保存到临时文件进行验证
            temp_config_path = f"{self.nginx_config_path}.tmp"
            self.nginx_generator.save_config(nginx_config, temp_config_path)
            
            # 验证配置语法
            is_valid, error_msg = self.nginx_generator.validate_nginx_config(temp_config_path)
            
            if is_valid:
                # 替换原配置文件
                os.rename(temp_config_path, self.nginx_config_path)
                
                # 重新加载Nginx配置
                if self.nginx_generator.reload_nginx_config():
                    logger.info("Nginx configuration updated and reloaded successfully")
                else:
                    logger.error("Failed to reload Nginx configuration")
            else:
                logger.error(f"Invalid Nginx configuration: {error_msg}")
                # 删除临时文件
                if os.path.exists(temp_config_path):
                    os.remove(temp_config_path)
                    
        except Exception as e:
            logger.error(f"Error updating Nginx configuration: {e}")
    
    def start(self):
        """启动迁移控制器"""
        logger.info("Starting Migration Controller...")
        
        try:
            # 加载初始配置
            initial_config = self.config_manager.load_config()
            if not initial_config:
                logger.error("Failed to load initial configuration")
                return False
            
            # 验证初始配置
            is_valid, message = self.config_manager.validate_config(initial_config)
            if not is_valid:
                logger.error(f"Invalid initial configuration: {message}")
                return False
            
            # 初始化组件
            self.config_manager.current_config = initial_config
            self.traffic_allocator.load_config(initial_config)
            
            # 生成初始Nginx配置
            self._update_nginx_config(initial_config)
            
            # 开始监控配置变更
            self.config_manager.start_watching()
            
            self.running = True
            logger.info("Migration Controller started successfully")
            
            return True
            
        except Exception as e:
            logger.error(f"Error starting Migration Controller: {e}")
            return False
    
    def stop(self):
        """停止迁移控制器"""
        logger.info("Stopping Migration Controller...")
        
        self.running = False
        
        # 停止配置监控
        self.config_manager.stop_watching()
        
        logger.info("Migration Controller stopped")
    
    def get_status(self) -> Dict:
        """获取控制器状态"""
        return {
            'running': self.running,
            'namespace': self.namespace,
            'configmap_name': self.configmap_name,
            'nginx_config_path': self.nginx_config_path,
            'last_config_hash': self.last_config_hash,
            'services': self.traffic_allocator.get_all_services_status()
        }
    
    def update_service_migration(self, service_name: str, percentage: int) -> bool:
        """更新服务迁移百分比"""
        try:
            success = self.config_manager.update_service_percentage(service_name, percentage)
            if success:
                logger.info(f"Updated {service_name} migration percentage to {percentage}%")
            return success
        except Exception as e:
            logger.error(f"Error updating service migration: {e}")
            return False
    
    def get_service_status(self, service_name: str) -> Dict:
        """获取服务状态"""
        return self.traffic_allocator.get_service_status(service_name)
    
    def run(self):
        """运行主循环"""
        if not self.start():
            logger.error("Failed to start Migration Controller")
            sys.exit(1)
        
        try:
            # 主循环
            while self.running:
                time.sleep(10)  # 每10秒检查一次状态
                
                # 可以在这里添加健康检查、指标收集等逻辑
                if self.running:
                    self._health_check()
                    
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        except Exception as e:
            logger.error(f"Error in main loop: {e}")
        finally:
            self.stop()
    
    def _health_check(self):
        """健康检查"""
        try:
            # 检查配置管理器状态
            current_config = self.config_manager.get_current_config()
            if not current_config:
                logger.warning("No configuration loaded")
                return
            
            # 检查Nginx配置文件是否存在
            if not os.path.exists(self.nginx_config_path):
                logger.warning(f"Nginx config file not found: {self.nginx_config_path}")
                return
            
            # 可以添加更多健康检查逻辑
            # 例如：检查上游服务器健康状态、监控指标等
            
        except Exception as e:
            logger.error(f"Health check error: {e}")


# CLI接口
def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description='K8s Cluster Migration Controller')
    parser.add_argument('--namespace', default='aibang-1111111111-bbdm',
                       help='Kubernetes namespace')
    parser.add_argument('--configmap', default='migration-config',
                       help='ConfigMap name')
    parser.add_argument('--config-key', default='migration.yaml',
                       help='Configuration key in ConfigMap')
    parser.add_argument('--nginx-config', default='/etc/nginx/conf.d/migration.conf',
                       help='Nginx configuration file path')
    parser.add_argument('--local-config', 
                       help='Local configuration file path (for development)')
    parser.add_argument('--log-level', default='INFO',
                       choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                       help='Log level')
    
    # 子命令
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # run命令
    run_parser = subparsers.add_parser('run', help='Run the migration controller')
    
    # status命令
    status_parser = subparsers.add_parser('status', help='Get controller status')
    
    # update命令
    update_parser = subparsers.add_parser('update', help='Update service migration percentage')
    update_parser.add_argument('service_name', help='Service name')
    update_parser.add_argument('percentage', type=int, help='Migration percentage (0-100)')
    
    args = parser.parse_args()
    
    # 设置日志级别
    logging.getLogger().setLevel(getattr(logging, args.log_level))
    
    # 创建控制器
    controller = MigrationController(
        namespace=args.namespace,
        configmap_name=args.configmap,
        config_key=args.config_key,
        nginx_config_path=args.nginx_config,
        local_config_path=args.local_config
    )
    
    # 执行命令
    if args.command == 'run':
        controller.run()
    elif args.command == 'status':
        if controller.start():
            status = controller.get_status()
            print(f"Controller Status: {status}")
            controller.stop()
        else:
            print("Failed to start controller")
            sys.exit(1)
    elif args.command == 'update':
        if controller.start():
            success = controller.update_service_migration(args.service_name, args.percentage)
            if success:
                print(f"Updated {args.service_name} to {args.percentage}%")
            else:
                print(f"Failed to update {args.service_name}")
                sys.exit(1)
            controller.stop()
        else:
            print("Failed to start controller")
            sys.exit(1)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()