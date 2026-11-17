#!/usr/bin/env python3
"""
配置管理器 - 实现配置热更新功能
Configuration Manager - Implements configuration hot update functionality
"""

import os
import time
import yaml
import threading
import logging
from typing import Dict, Callable, Optional
from pathlib import Path
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ConfigManager:
    """配置管理器 - 支持ConfigMap热更新"""
    
    def __init__(self, 
                 namespace: str = "aibang-1111111111-bbdm",
                 configmap_name: str = "migration-config",
                 config_key: str = "migration.yaml",
                 local_config_path: Optional[str] = None):
        """
        初始化配置管理器
        
        Args:
            namespace: K8s命名空间
            configmap_name: ConfigMap名称
            config_key: ConfigMap中的配置键
            local_config_path: 本地配置文件路径（用于开发环境）
        """
        self.namespace = namespace
        self.configmap_name = configmap_name
        self.config_key = config_key
        self.local_config_path = local_config_path
        
        self.current_config: Dict = {}
        self.config_version: str = ""
        self.callbacks: list[Callable[[Dict], None]] = []
        
        # K8s客户端
        self.k8s_client: Optional[client.CoreV1Api] = None
        self.watch_thread: Optional[threading.Thread] = None
        self.stop_watching = threading.Event()
        
        # 文件监控
        self.file_watch_thread: Optional[threading.Thread] = None
        self.last_file_mtime: float = 0
        
        self._init_k8s_client()
    
    def _init_k8s_client(self):
        """初始化K8s客户端"""
        try:
            # 尝试加载集群内配置
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes configuration")
        except config.ConfigException:
            try:
                # 尝试加载本地配置
                config.load_kube_config()
                logger.info("Loaded local Kubernetes configuration")
            except config.ConfigException:
                logger.warning("Could not load Kubernetes configuration, using local file mode only")
                return
        
        self.k8s_client = client.CoreV1Api()
    
    def add_config_callback(self, callback: Callable[[Dict], None]):
        """添加配置变更回调函数"""
        self.callbacks.append(callback)
    
    def remove_config_callback(self, callback: Callable[[Dict], None]):
        """移除配置变更回调函数"""
        if callback in self.callbacks:
            self.callbacks.remove(callback)
    
    def _notify_callbacks(self, config_data: Dict):
        """通知所有回调函数"""
        for callback in self.callbacks:
            try:
                callback(config_data)
            except Exception as e:
                logger.error(f"Error in config callback: {e}")
    
    def load_config(self) -> Dict:
        """加载配置"""
        if self.local_config_path and os.path.exists(self.local_config_path):
            return self._load_from_file()
        elif self.k8s_client:
            return self._load_from_configmap()
        else:
            logger.error("No configuration source available")
            return {}
    
    def _load_from_file(self) -> Dict:
        """从本地文件加载配置"""
        try:
            with open(self.local_config_path, 'r', encoding='utf-8') as f:
                config_data = yaml.safe_load(f)
            
            # 更新文件修改时间
            self.last_file_mtime = os.path.getmtime(self.local_config_path)
            
            logger.info(f"Loaded configuration from file: {self.local_config_path}")
            return config_data
        except Exception as e:
            logger.error(f"Error loading configuration from file: {e}")
            return {}
    
    def _load_from_configmap(self) -> Dict:
        """从ConfigMap加载配置"""
        try:
            configmap = self.k8s_client.read_namespaced_config_map(
                name=self.configmap_name,
                namespace=self.namespace
            )
            
            if self.config_key not in configmap.data:
                logger.error(f"Config key '{self.config_key}' not found in ConfigMap")
                return {}
            
            config_yaml = configmap.data[self.config_key]
            config_data = yaml.safe_load(config_yaml)
            
            # 更新配置版本
            self.config_version = configmap.metadata.resource_version
            
            logger.info(f"Loaded configuration from ConfigMap: {self.configmap_name}")
            return config_data
            
        except ApiException as e:
            logger.error(f"Error loading ConfigMap: {e}")
            return {}
        except Exception as e:
            logger.error(f"Error parsing configuration: {e}")
            return {}
    
    def start_watching(self):
        """开始监控配置变更"""
        if self.local_config_path:
            self._start_file_watching()
        elif self.k8s_client:
            self._start_configmap_watching()
        else:
            logger.warning("No configuration source to watch")
    
    def stop_watching(self):
        """停止监控配置变更"""
        self.stop_watching.set()
        
        if self.watch_thread and self.watch_thread.is_alive():
            self.watch_thread.join(timeout=5)
        
        if self.file_watch_thread and self.file_watch_thread.is_alive():
            self.file_watch_thread.join(timeout=5)
    
    def _start_file_watching(self):
        """开始监控本地文件变更"""
        def watch_file():
            logger.info(f"Starting file watcher for: {self.local_config_path}")
            
            while not self.stop_watching.is_set():
                try:
                    if os.path.exists(self.local_config_path):
                        current_mtime = os.path.getmtime(self.local_config_path)
                        
                        if current_mtime > self.last_file_mtime:
                            logger.info("Configuration file changed, reloading...")
                            new_config = self._load_from_file()
                            
                            if new_config != self.current_config:
                                self.current_config = new_config
                                self._notify_callbacks(new_config)
                    
                    time.sleep(1)  # 检查间隔1秒
                    
                except Exception as e:
                    logger.error(f"Error in file watcher: {e}")
                    time.sleep(5)
        
        self.file_watch_thread = threading.Thread(target=watch_file, daemon=True)
        self.file_watch_thread.start()
    
    def _start_configmap_watching(self):
        """开始监控ConfigMap变更"""
        def watch_configmap():
            logger.info(f"Starting ConfigMap watcher for: {self.namespace}/{self.configmap_name}")
            
            while not self.stop_watching.is_set():
                try:
                    w = watch.Watch()
                    
                    # 监控ConfigMap变更事件
                    for event in w.stream(
                        self.k8s_client.list_namespaced_config_map,
                        namespace=self.namespace,
                        field_selector=f"metadata.name={self.configmap_name}",
                        timeout_seconds=30
                    ):
                        if self.stop_watching.is_set():
                            break
                        
                        event_type = event['type']
                        configmap = event['object']
                        
                        logger.info(f"ConfigMap event: {event_type}")
                        
                        if event_type in ['ADDED', 'MODIFIED']:
                            new_version = configmap.metadata.resource_version
                            
                            # 检查版本是否变更
                            if new_version != self.config_version:
                                logger.info("ConfigMap version changed, reloading configuration...")
                                new_config = self._load_from_configmap()
                                
                                if new_config != self.current_config:
                                    self.current_config = new_config
                                    self._notify_callbacks(new_config)
                        
                        elif event_type == 'DELETED':
                            logger.warning("ConfigMap was deleted!")
                            self.current_config = {}
                            self._notify_callbacks({})
                    
                except Exception as e:
                    logger.error(f"Error in ConfigMap watcher: {e}")
                    time.sleep(5)  # 等待5秒后重试
        
        self.watch_thread = threading.Thread(target=watch_configmap, daemon=True)
        self.watch_thread.start()
    
    def get_current_config(self) -> Dict:
        """获取当前配置"""
        return self.current_config.copy()
    
    def validate_config(self, config_data: Dict) -> tuple[bool, str]:
        """验证配置格式"""
        try:
            # 检查必需的顶级字段
            if 'services' not in config_data:
                return False, "Missing 'services' field in configuration"
            
            services = config_data['services']
            if not isinstance(services, list):
                return False, "'services' must be a list"
            
            # 验证每个服务配置
            for i, service in enumerate(services):
                if not isinstance(service, dict):
                    return False, f"Service {i} must be a dictionary"
                
                # 检查必需字段
                required_fields = [
                    'name', 'old_host', 'old_backend', 'old_protocol',
                    'new_host', 'new_backend', 'new_protocol', 'migration', 'fallback'
                ]
                
                for field in required_fields:
                    if field not in service:
                        return False, f"Service {i} missing required field: {field}"
                
                # 验证migration配置
                migration = service['migration']
                if not isinstance(migration, dict):
                    return False, f"Service {i} 'migration' must be a dictionary"
                
                migration_required = ['enabled', 'strategy', 'percentage']
                for field in migration_required:
                    if field not in migration:
                        return False, f"Service {i} migration missing field: {field}"
                
                # 验证百分比范围
                percentage = migration['percentage']
                if not isinstance(percentage, int) or percentage < 0 or percentage > 100:
                    return False, f"Service {i} migration percentage must be 0-100"
                
                # 验证fallback配置
                fallback = service['fallback']
                if not isinstance(fallback, dict):
                    return False, f"Service {i} 'fallback' must be a dictionary"
                
                fallback_required = ['enabled', 'max_failures', 'failure_window', 'recovery_time']
                for field in fallback_required:
                    if field not in fallback:
                        return False, f"Service {i} fallback missing field: {field}"
            
            return True, "Configuration is valid"
            
        except Exception as e:
            return False, f"Configuration validation error: {str(e)}"
    
    def update_service_percentage(self, service_name: str, percentage: int) -> bool:
        """更新服务的迁移百分比"""
        if not (0 <= percentage <= 100):
            logger.error(f"Invalid percentage: {percentage}. Must be 0-100")
            return False
        
        try:
            # 更新本地配置
            for service in self.current_config.get('services', []):
                if service['name'] == service_name:
                    service['migration']['percentage'] = percentage
                    break
            else:
                logger.error(f"Service {service_name} not found")
                return False
            
            # 如果使用ConfigMap，更新ConfigMap
            if self.k8s_client and not self.local_config_path:
                return self._update_configmap()
            
            # 如果使用本地文件，写入文件
            elif self.local_config_path:
                return self._update_local_file()
            
            return True
            
        except Exception as e:
            logger.error(f"Error updating service percentage: {e}")
            return False
    
    def _update_configmap(self) -> bool:
        """更新ConfigMap"""
        try:
            # 读取当前ConfigMap
            configmap = self.k8s_client.read_namespaced_config_map(
                name=self.configmap_name,
                namespace=self.namespace
            )
            
            # 更新配置数据
            config_yaml = yaml.dump(self.current_config, default_flow_style=False, allow_unicode=True)
            configmap.data[self.config_key] = config_yaml
            
            # 应用更新
            self.k8s_client.patch_namespaced_config_map(
                name=self.configmap_name,
                namespace=self.namespace,
                body=configmap
            )
            
            logger.info("ConfigMap updated successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error updating ConfigMap: {e}")
            return False
    
    def _update_local_file(self) -> bool:
        """更新本地配置文件"""
        try:
            with open(self.local_config_path, 'w', encoding='utf-8') as f:
                yaml.dump(self.current_config, f, default_flow_style=False, allow_unicode=True)
            
            logger.info("Local configuration file updated successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error updating local file: {e}")
            return False


# 示例使用
if __name__ == "__main__":
    # 创建配置管理器
    config_manager = ConfigManager(
        namespace="aibang-1111111111-bbdm",
        configmap_name="migration-config",
        config_key="migration.yaml",
        local_config_path="./config/migration.yaml"  # 开发环境使用本地文件
    )
    
    # 添加配置变更回调
    def on_config_change(new_config):
        print(f"Configuration changed: {len(new_config.get('services', []))} services")
    
    config_manager.add_config_callback(on_config_change)
    
    # 加载初始配置
    initial_config = config_manager.load_config()
    config_manager.current_config = initial_config
    
    # 验证配置
    is_valid, message = config_manager.validate_config(initial_config)
    print(f"Configuration validation: {is_valid}, {message}")
    
    # 开始监控配置变更
    config_manager.start_watching()
    
    try:
        # 保持程序运行
        while True:
            time.sleep(10)
            
            # 示例：动态更新配置
            current_config = config_manager.get_current_config()
            if current_config.get('services'):
                service_name = current_config['services'][0]['name']
                current_percentage = current_config['services'][0]['migration']['percentage']
                
                # 每10秒增加5%的流量到新集群（仅作演示）
                new_percentage = min(current_percentage + 5, 100)
                if new_percentage != current_percentage:
                    print(f"Updating {service_name} percentage to {new_percentage}%")
                    config_manager.update_service_percentage(service_name, new_percentage)
    
    except KeyboardInterrupt:
        print("Stopping configuration manager...")
        config_manager.stop_watching()