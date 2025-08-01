#!/usr/bin/env python3
"""
Python版本的容器启动校验器
适用于Python应用的内置校验逻辑
"""

import os
import sys
import logging
import requests
from typing import List, Optional
from dataclasses import dataclass

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - [VALIDATOR] - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class BuildInfo:
    """构建信息数据类"""
    git_branch: str
    git_commit: str
    build_time: str
    build_user: str

class ContainerValidator:
    """容器启动校验器"""
    
    def __init__(self):
        self.production_projects = [
            "myproject-prd", 
            "myproject-prod", 
            "myproject-production"
        ]
        self.pre_production_projects = [
            "myproject-ppd", 
            "myproject-preprod"
        ]
        self.required_branch_prefix = "master"
        
    def get_project_id(self) -> Optional[str]:
        """获取GCP项目ID"""
        # 方法1: 从元数据服务获取
        try:
            headers = {"Metadata-Flavor": "Google"}
            response = requests.get(
                "http://metadata.google.internal/computeMetadata/v1/project/project-id",
                headers=headers,
                timeout=5
            )
            if response.status_code == 200:
                return response.text.strip()
        except Exception as e:
            logger.debug(f"无法从元数据服务获取项目ID: {e}")
        
        # 方法2: 从环境变量获取
        project_id = os.getenv("GOOGLE_CLOUD_PROJECT")
        if project_id:
            return project_id
            
        # 方法3: 从其他环境变量获取
        project_id = os.getenv("GCP_PROJECT")
        if project_id:
            return project_id
            
        return None
    
    def get_build_info(self) -> BuildInfo:
        """获取构建信息"""
        return BuildInfo(
            git_branch=os.getenv("GIT_BRANCH", "unknown"),
            git_commit=os.getenv("GIT_COMMIT", "unknown"),
            build_time=os.getenv("BUILD_TIME", "unknown"),
            build_user=os.getenv("BUILD_USER", "unknown")
        )
    
    def is_production_project(self, project_id: str) -> bool:
        """检查是否为生产环境项目"""
        return project_id in self.production_projects
    
    def is_pre_production_project(self, project_id: str) -> bool:
        """检查是否为预生产环境项目"""
        return project_id in self.pre_production_projects
    
    def validate_production_deployment(self, project_id: str, build_info: BuildInfo) -> bool:
        """校验生产环境部署"""
        logger.warning(f"🔒 检测到生产环境项目: {project_id}")
        logger.warning("执行严格校验...")
        
        # 校验1: 检查分支
        if not build_info.git_branch.startswith(self.required_branch_prefix):
            logger.error("❌ 生产环境校验失败!")
            logger.error(f"生产环境只能部署来自 {self.required_branch_prefix} 分支的镜像")
            logger.error(f"当前分支: {build_info.git_branch}")
            logger.error(f"要求分支前缀: {self.required_branch_prefix}")
            return False
        
        # 校验2: 检查生产环境批准标识
        if not os.getenv("PRODUCTION_APPROVED"):
            logger.error("❌ 生产环境校验失败!")
            logger.error("缺少生产环境批准标识 (PRODUCTION_APPROVED)")
            logger.error("请确保通过正确的部署流程部署到生产环境")
            return False
        
        # 校验3: 检查必需的环境变量
        required_env_vars = ["DATABASE_URL", "API_KEY", "SECRET_KEY"]
        for var in required_env_vars:
            if not os.getenv(var):
                logger.error("❌ 生产环境校验失败!")
                logger.error(f"缺少必需的环境变量: {var}")
                return False
        
        # 校验4: 检查敏感配置
        if self._check_debug_mode():
            logger.error("❌ 生产环境校验失败!")
            logger.error("生产环境不能启用调试模式")
            return False
        
        logger.info("✅ 生产环境校验通过")
        return True
    
    def validate_pre_production_deployment(self, project_id: str, build_info: BuildInfo) -> bool:
        """校验预生产环境部署"""
        logger.warning(f"🧪 检测到预生产环境项目: {project_id}")
        
        # 预生产环境的校验相对宽松
        if build_info.git_branch == "unknown":
            logger.warning("⚠️  无法确定构建分支，请检查构建流程")
        
        logger.info("✅ 预生产环境校验通过")
        return True
    
    def _check_debug_mode(self) -> bool:
        """检查是否启用了调试模式"""
        debug_indicators = [
            os.getenv("DEBUG", "").lower() in ["true", "1", "yes"],
            os.getenv("NODE_ENV", "").lower() == "development",
            os.getenv("FLASK_ENV", "").lower() == "development",
            os.getenv("DJANGO_DEBUG", "").lower() in ["true", "1"],
        ]
        return any(debug_indicators)
    
    def validate(self) -> bool:
        """执行完整的校验流程"""
        logger.info("🚀 开始容器启动校验...")
        
        # 获取项目ID
        project_id = self.get_project_id()
        if not project_id:
            logger.error("❌ 无法获取GCP项目ID")
            logger.error("请确保容器运行在Cloud Run环境中")
            return False
        
        logger.info(f"当前项目: {project_id}")
        
        # 获取构建信息
        build_info = self.get_build_info()
        logger.debug(f"构建信息: {build_info}")
        
        # 根据项目类型执行不同的校验
        if self.is_production_project(project_id):
            return self.validate_production_deployment(project_id, build_info)
        elif self.is_pre_production_project(project_id):
            return self.validate_pre_production_deployment(project_id, build_info)
        else:
            logger.info("ℹ️  开发/测试环境，跳过严格校验")
            return True

def main():
    """主函数"""
    validator = ContainerValidator()
    
    try:
        if validator.validate():
            logger.info("🎉 容器启动校验完成，继续启动应用...")
            sys.exit(0)
        else:
            logger.error("🚫 容器启动校验失败，阻止应用启动")
            sys.exit(1)
    except Exception as e:
        logger.error(f"❌ 校验过程中发生异常: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()