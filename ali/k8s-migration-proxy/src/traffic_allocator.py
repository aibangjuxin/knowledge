#!/usr/bin/env python3
"""
流量分配器 - 实现基于权重的流量分配逻辑
Traffic Allocator - Implements weight-based traffic allocation logic
"""

import hashlib
import ipaddress
import random
import time
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum


class TargetCluster(Enum):
    OLD = "old_cluster"
    NEW = "new_cluster"


@dataclass
class ServiceConfig:
    """服务配置数据类"""
    name: str
    old_host: str
    old_backend: str
    old_protocol: str
    new_host: str
    new_backend: str
    new_protocol: str
    migration_enabled: bool
    strategy: str
    percentage: int
    header_rules: List[Dict]
    ip_rules: List[Dict]
    user_rules: List[Dict]
    fallback_enabled: bool
    max_failures: int
    failure_window: int
    recovery_time: int


@dataclass
class RequestContext:
    """请求上下文"""
    headers: Dict[str, str]
    client_ip: str
    path: str
    method: str
    timestamp: float = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = time.time()


class TrafficAllocator:
    """流量分配器"""
    
    def __init__(self):
        self.services: Dict[str, ServiceConfig] = {}
        self.failure_counts: Dict[str, Dict[str, int]] = {}
        self.failure_windows: Dict[str, Dict[str, float]] = {}
        self.recovery_times: Dict[str, Dict[str, float]] = {}
        
    def load_config(self, config: Dict) -> None:
        """加载配置"""
        self.services.clear()
        
        for service_config in config.get('services', []):
            service = ServiceConfig(
                name=service_config['name'],
                old_host=service_config['old_host'],
                old_backend=service_config['old_backend'],
                old_protocol=service_config['old_protocol'],
                new_host=service_config['new_host'],
                new_backend=service_config['new_backend'],
                new_protocol=service_config['new_protocol'],
                migration_enabled=service_config['migration']['enabled'],
                strategy=service_config['migration']['strategy'],
                percentage=service_config['migration']['percentage'],
                header_rules=service_config.get('canary', {}).get('header_rules', []),
                ip_rules=service_config.get('canary', {}).get('ip_rules', []),
                user_rules=service_config.get('canary', {}).get('user_rules', []),
                fallback_enabled=service_config['fallback']['enabled'],
                max_failures=service_config['fallback']['max_failures'],
                failure_window=service_config['fallback']['failure_window'],
                recovery_time=service_config['fallback']['recovery_time']
            )
            
            self.services[service.name] = service
            
            # 初始化失败计数器
            if service.name not in self.failure_counts:
                self.failure_counts[service.name] = {
                    TargetCluster.OLD.value: 0,
                    TargetCluster.NEW.value: 0
                }
                self.failure_windows[service.name] = {
                    TargetCluster.OLD.value: 0,
                    TargetCluster.NEW.value: 0
                }
                self.recovery_times[service.name] = {
                    TargetCluster.OLD.value: 0,
                    TargetCluster.NEW.value: 0
                }
    
    def allocate_traffic(self, service_name: str, request: RequestContext) -> Tuple[TargetCluster, str]:
        """
        分配流量到目标集群
        
        Args:
            service_name: 服务名称
            request: 请求上下文
            
        Returns:
            Tuple[TargetCluster, str]: (目标集群, 后端地址)
        """
        if service_name not in self.services:
            raise ValueError(f"Service {service_name} not found in configuration")
            
        service = self.services[service_name]
        
        # 如果迁移未启用，直接返回旧集群
        if not service.migration_enabled:
            return TargetCluster.OLD, service.old_backend
            
        # 检查降级状态
        if self._should_fallback(service_name, TargetCluster.NEW):
            return TargetCluster.OLD, service.old_backend
            
        # 根据策略分配流量
        target = self._determine_target(service, request)
        
        if target == TargetCluster.NEW:
            return target, service.new_backend
        else:
            return target, service.old_backend
    
    def _determine_target(self, service: ServiceConfig, request: RequestContext) -> TargetCluster:
        """确定目标集群"""
        
        # 1. 检查基于请求头的规则
        for rule in service.header_rules:
            header_name = rule['header']
            header_value = rule['value']
            target = rule['target']
            
            if request.headers.get(header_name) == header_value:
                if target == "new_cluster":
                    return TargetCluster.NEW
                else:
                    return TargetCluster.OLD
        
        # 2. 检查基于IP的规则
        for rule in service.ip_rules:
            cidr = rule['cidr']
            target = rule['target']
            
            try:
                if ipaddress.ip_address(request.client_ip) in ipaddress.ip_network(cidr):
                    if target == "new_cluster":
                        return TargetCluster.NEW
                    else:
                        return TargetCluster.OLD
            except ValueError:
                # 无效IP地址，跳过此规则
                continue
        
        # 3. 检查基于用户ID的规则
        for rule in service.user_rules:
            user_id_header = rule['user_id_header']
            hash_range = rule['hash_range']
            target = rule['target']
            
            user_id = request.headers.get(user_id_header)
            if user_id:
                # 计算用户ID的哈希值
                hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16) % 100
                
                # 解析哈希范围 (例如: "0-10")
                range_parts = hash_range.split('-')
                if len(range_parts) == 2:
                    min_range = int(range_parts[0])
                    max_range = int(range_parts[1])
                    
                    if min_range <= hash_value <= max_range:
                        if target == "new_cluster":
                            return TargetCluster.NEW
                        else:
                            return TargetCluster.OLD
        
        # 4. 基于权重的随机分配
        if service.strategy == "weight":
            return self._weight_based_allocation(service.percentage)
        
        # 默认返回旧集群
        return TargetCluster.OLD
    
    def _weight_based_allocation(self, percentage: int) -> TargetCluster:
        """基于权重的分配"""
        if percentage <= 0:
            return TargetCluster.OLD
        elif percentage >= 100:
            return TargetCluster.NEW
        else:
            # 生成0-99的随机数
            random_value = random.randint(0, 99)
            if random_value < percentage:
                return TargetCluster.NEW
            else:
                return TargetCluster.OLD
    
    def record_failure(self, service_name: str, target: TargetCluster) -> None:
        """记录失败"""
        if service_name not in self.services:
            return
            
        current_time = time.time()
        service = self.services[service_name]
        target_key = target.value
        
        # 检查是否在新的失败窗口内
        if (current_time - self.failure_windows[service_name][target_key]) > service.failure_window:
            # 重置失败计数器
            self.failure_counts[service_name][target_key] = 0
            self.failure_windows[service_name][target_key] = current_time
        
        # 增加失败计数
        self.failure_counts[service_name][target_key] += 1
        
        # 如果达到最大失败次数，设置恢复时间
        if self.failure_counts[service_name][target_key] >= service.max_failures:
            self.recovery_times[service_name][target_key] = current_time + service.recovery_time
    
    def record_success(self, service_name: str, target: TargetCluster) -> None:
        """记录成功"""
        if service_name not in self.services:
            return
            
        target_key = target.value
        
        # 重置失败计数器
        self.failure_counts[service_name][target_key] = 0
        self.recovery_times[service_name][target_key] = 0
    
    def _should_fallback(self, service_name: str, target: TargetCluster) -> bool:
        """检查是否应该降级"""
        if service_name not in self.services:
            return False
            
        service = self.services[service_name]
        if not service.fallback_enabled:
            return False
            
        target_key = target.value
        current_time = time.time()
        
        # 检查是否在恢复期内
        if self.recovery_times[service_name][target_key] > current_time:
            return True
            
        # 检查失败次数是否超过阈值
        if self.failure_counts[service_name][target_key] >= service.max_failures:
            return True
            
        return False
    
    def get_service_status(self, service_name: str) -> Dict:
        """获取服务状态"""
        if service_name not in self.services:
            return {}
            
        service = self.services[service_name]
        current_time = time.time()
        
        return {
            'name': service.name,
            'migration_enabled': service.migration_enabled,
            'strategy': service.strategy,
            'percentage': service.percentage,
            'old_cluster': {
                'backend': service.old_backend,
                'failure_count': self.failure_counts[service_name][TargetCluster.OLD.value],
                'in_recovery': self.recovery_times[service_name][TargetCluster.OLD.value] > current_time
            },
            'new_cluster': {
                'backend': service.new_backend,
                'failure_count': self.failure_counts[service_name][TargetCluster.NEW.value],
                'in_recovery': self.recovery_times[service_name][TargetCluster.NEW.value] > current_time
            }
        }
    
    def get_all_services_status(self) -> List[Dict]:
        """获取所有服务状态"""
        return [self.get_service_status(name) for name in self.services.keys()]


# 示例使用
if __name__ == "__main__":
    # 创建流量分配器实例
    allocator = TrafficAllocator()
    
    # 示例配置
    config = {
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
                    'ip_rules': [],
                    'user_rules': []
                },
                'fallback': {
                    'enabled': True,
                    'max_failures': 5,
                    'failure_window': 60,
                    'recovery_time': 300
                }
            }
        ]
    }
    
    # 加载配置
    allocator.load_config(config)
    
    # 测试流量分配
    request = RequestContext(
        headers={'X-Migration-Target': 'new'},
        client_ip='10.0.0.1',
        path='/api/test',
        method='GET'
    )
    
    target, backend = allocator.allocate_traffic('api-name01', request)
    print(f"Target: {target}, Backend: {backend}")
    
    # 获取服务状态
    status = allocator.get_service_status('api-name01')
    print(f"Service Status: {status}")