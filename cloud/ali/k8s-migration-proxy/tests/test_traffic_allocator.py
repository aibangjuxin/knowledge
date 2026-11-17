#!/usr/bin/env python3
"""
流量分配器测试
Traffic Allocator Tests
"""

import pytest
import sys
import os

# 添加src目录到Python路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from traffic_allocator import TrafficAllocator, RequestContext, TargetCluster


class TestTrafficAllocator:
    """流量分配器测试类"""
    
    def setup_method(self):
        """测试前设置"""
        self.allocator = TrafficAllocator()
        self.test_config = {
            'services': [
                {
                    'name': 'test-service',
                    'old_host': 'test.old.com',
                    'old_backend': 'old-backend:8080',
                    'old_protocol': 'http',
                    'new_host': 'test.new.com',
                    'new_backend': 'new-backend:443',
                    'new_protocol': 'https',
                    'migration': {
                        'enabled': True,
                        'strategy': 'weight',
                        'percentage': 50
                    },
                    'canary': {
                        'header_rules': [
                            {'header': 'X-Migration-Target', 'value': 'new', 'target': 'new_cluster'}
                        ],
                        'ip_rules': [
                            {'cidr': '10.0.0.0/8', 'target': 'new_cluster'}
                        ],
                        'user_rules': [
                            {'user_id_header': 'X-User-ID', 'hash_range': '0-10', 'target': 'new_cluster'}
                        ]
                    },
                    'fallback': {
                        'enabled': True,
                        'max_failures': 3,
                        'failure_window': 60,
                        'recovery_time': 300
                    }
                }
            ]
        }
    
    def test_load_config(self):
        """测试配置加载"""
        self.allocator.load_config(self.test_config)
        assert 'test-service' in self.allocator.services
        
        service = self.allocator.services['test-service']
        assert service.name == 'test-service'
        assert service.migration_enabled == True
        assert service.percentage == 50
    
    def test_header_based_routing(self):
        """测试基于请求头的路由"""
        self.allocator.load_config(self.test_config)
        
        # 测试路由到新集群的请求头
        request = RequestContext(
            headers={'X-Migration-Target': 'new'},
            client_ip='192.168.1.1',
            path='/test',
            method='GET'
        )
        
        target, backend = self.allocator.allocate_traffic('test-service', request)
        assert target == TargetCluster.NEW
        assert backend == 'new-backend:443'
    
    def test_ip_based_routing(self):
        """测试基于IP的路由"""
        self.allocator.load_config(self.test_config)
        
        # 测试10.0.0.0/8网段的IP
        request = RequestContext(
            headers={},
            client_ip='10.0.0.100',
            path='/test',
            method='GET'
        )
        
        target, backend = self.allocator.allocate_traffic('test-service', request)
        assert target == TargetCluster.NEW
        assert backend == 'new-backend:443'
    
    def test_weight_based_allocation(self):
        """测试基于权重的分配"""
        self.allocator.load_config(self.test_config)
        
        # 测试多次请求的分配结果
        new_count = 0
        old_count = 0
        total_requests = 1000
        
        for i in range(total_requests):
            request = RequestContext(
                headers={},
                client_ip='192.168.1.1',
                path='/test',
                method='GET'
            )
            
            target, _ = self.allocator.allocate_traffic('test-service', request)
            if target == TargetCluster.NEW:
                new_count += 1
            else:
                old_count += 1
        
        # 50%的权重，允许5%的误差
        expected_new = total_requests * 0.5
        assert abs(new_count - expected_new) < total_requests * 0.05
    
    def test_migration_disabled(self):
        """测试迁移禁用时的行为"""
        config = self.test_config.copy()
        config['services'][0]['migration']['enabled'] = False
        
        self.allocator.load_config(config)
        
        request = RequestContext(
            headers={'X-Migration-Target': 'new'},
            client_ip='10.0.0.100',
            path='/test',
            method='GET'
        )
        
        target, backend = self.allocator.allocate_traffic('test-service', request)
        assert target == TargetCluster.OLD
        assert backend == 'old-backend:8080'
    
    def test_failure_handling(self):
        """测试失败处理"""
        self.allocator.load_config(self.test_config)
        
        # 记录多次失败
        for _ in range(3):
            self.allocator.record_failure('test-service', TargetCluster.NEW)
        
        # 检查是否应该降级
        assert self.allocator._should_fallback('test-service', TargetCluster.NEW) == True
        
        # 记录成功，应该重置失败计数
        self.allocator.record_success('test-service', TargetCluster.NEW)
        assert self.allocator._should_fallback('test-service', TargetCluster.NEW) == False
    
    def test_service_status(self):
        """测试服务状态获取"""
        self.allocator.load_config(self.test_config)
        
        status = self.allocator.get_service_status('test-service')
        
        assert status['name'] == 'test-service'
        assert status['migration_enabled'] == True
        assert status['percentage'] == 50
        assert 'old_cluster' in status
        assert 'new_cluster' in status
    
    def test_invalid_service(self):
        """测试无效服务名"""
        self.allocator.load_config(self.test_config)
        
        request = RequestContext(
            headers={},
            client_ip='192.168.1.1',
            path='/test',
            method='GET'
        )
        
        with pytest.raises(ValueError):
            self.allocator.allocate_traffic('invalid-service', request)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])