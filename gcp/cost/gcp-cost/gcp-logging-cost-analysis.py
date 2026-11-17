#!/usr/bin/env python3
"""
GCP 日志成本分析脚本

此脚本用于分析 GCP 项目的日志成本，包括：
1. 获取日志使用量统计
2. 分析成本趋势
3. 生成优化建议报告
4. 预测成本节省效果

依赖:
- google-cloud-logging
- google-cloud-billing
- google-cloud-monitoring
- pandas
- matplotlib

安装依赖:
pip install google-cloud-logging google-cloud-billing google-cloud-monitoring pandas matplotlib
"""

import os
import sys
import json
import argparse
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import pandas as pd
import matplotlib.pyplot as plt
from google.cloud import logging
from google.cloud import monitoring_v3
from google.oauth2 import service_account
import warnings
warnings.filterwarnings('ignore')

class GCPLoggingCostAnalyzer:
    """GCP 日志成本分析器"""
    
    def __init__(self, project_id: str, credentials_path: Optional[str] = None):
        """
        初始化分析器
        
        Args:
            project_id: GCP 项目 ID
            credentials_path: 服务账号密钥文件路径（可选）
        """
        self.project_id = project_id
        
        # 初始化客户端
        if credentials_path:
            credentials = service_account.Credentials.from_service_account_file(credentials_path)
            self.logging_client = logging.Client(project=project_id, credentials=credentials)
            self.monitoring_client = monitoring_v3.MetricServiceClient(credentials=credentials)
        else:
            self.logging_client = logging.Client(project=project_id)
            self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        # 成本常量（美元）
        self.INGESTION_COST_PER_GIB = 0.50
        self.STORAGE_COST_PER_GIB_MONTH = 0.01
        self.FREE_TIER_GIB = 50
        
        print(f"✅ 已初始化项目 {project_id} 的日志成本分析器")
    
    def get_log_volume_stats(self, days: int = 30) -> Dict:
        """
        获取指定天数内的日志量统计
        
        Args:
            days: 分析的天数
            
        Returns:
            包含日志量统计的字典
        """
        print(f"📊 分析最近 {days} 天的日志量...")
        
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(days=days)
        
        # 构建查询过滤器
        filter_str = f'timestamp>="{start_time.isoformat()}Z" AND timestamp<="{end_time.isoformat()}Z"'
        
        stats = {
            'total_entries': 0,
            'by_resource_type': {},
            'by_severity': {},
            'by_day': {},
            'estimated_size_gib': 0
        }
        
        try:
            # 获取日志条目
            entries = self.logging_client.list_entries(filter_=filter_str, page_size=1000)
            
            for entry in entries:
                stats['total_entries'] += 1
                
                # 按资源类型统计
                resource_type = entry.resource.type if entry.resource else 'unknown'
                stats['by_resource_type'][resource_type] = stats['by_resource_type'].get(resource_type, 0) + 1
                
                # 按严重性统计
                severity = entry.severity.name if entry.severity else 'UNKNOWN'
                stats['by_severity'][severity] = stats['by_severity'].get(severity, 0) + 1
                
                # 按日期统计
                day = entry.timestamp.date().isoformat()
                stats['by_day'][day] = stats['by_day'].get(day, 0) + 1
                
                # 估算大小（每条日志平均 1KB）
                stats['estimated_size_gib'] += 0.001 / 1024  # 1KB to GiB
        
        except Exception as e:
            print(f"⚠️  获取日志统计时出错: {e}")
            return stats
        
        print(f"✅ 分析完成，共处理 {stats['total_entries']} 条日志")
        return stats
    
    def analyze_cost_by_resource_type(self, stats: Dict) -> pd.DataFrame:
        """
        按资源类型分析成本
        
        Args:
            stats: 日志量统计数据
            
        Returns:
            成本分析 DataFrame
        """
        print("💰 分析各资源类型的成本...")
        
        resource_data = []
        total_size_gib = stats['estimated_size_gib']
        
        for resource_type, count in stats['by_resource_type'].items():
            # 计算该资源类型的大小占比
            size_ratio = count / stats['total_entries'] if stats['total_entries'] > 0 else 0
            size_gib = total_size_gib * size_ratio
            
            # 计算成本
            ingestion_cost = max(0, size_gib - self.FREE_TIER_GIB) * self.INGESTION_COST_PER_GIB
            storage_cost = size_gib * self.STORAGE_COST_PER_GIB_MONTH
            total_cost = ingestion_cost + storage_cost
            
            resource_data.append({
                'resource_type': resource_type,
                'log_count': count,
                'size_gib': round(size_gib, 3),
                'ingestion_cost': round(ingestion_cost, 2),
                'storage_cost': round(storage_cost, 2),
                'total_cost': round(total_cost, 2),
                'percentage': round(size_ratio * 100, 1)
            })
        
        df = pd.DataFrame(resource_data)
        df = df.sort_values('total_cost', ascending=False)
        
        return df
    
    def generate_optimization_recommendations(self, cost_df: pd.DataFrame, stats: Dict) -> List[Dict]:
        """
        生成成本优化建议
        
        Args:
            cost_df: 成本分析 DataFrame
            stats: 日志量统计
            
        Returns:
            优化建议列表
        """
        print("🎯 生成成本优化建议...")
        
        recommendations = []
        
        # 1. 高成本资源类型建议
        high_cost_resources = cost_df[cost_df['total_cost'] > 10].head(3)
        if not high_cost_resources.empty:
            for _, row in high_cost_resources.iterrows():
                recommendations.append({
                    'type': 'high_cost_resource',
                    'priority': 'HIGH',
                    'resource_type': row['resource_type'],
                    'current_cost': row['total_cost'],
                    'recommendation': f"考虑为 {row['resource_type']} 添加排除过滤器，当前月成本约 ${row['total_cost']}",
                    'potential_savings': round(row['total_cost'] * 0.6, 2)
                })
        
        # 2. 日志级别优化建议
        severity_stats = stats['by_severity']
        debug_info_count = severity_stats.get('DEBUG', 0) + severity_stats.get('INFO', 0)
        total_count = stats['total_entries']
        
        if debug_info_count > total_count * 0.5:  # 超过50%是DEBUG/INFO日志
            potential_savings = (debug_info_count / total_count) * stats['estimated_size_gib'] * self.INGESTION_COST_PER_GIB
            recommendations.append({
                'type': 'severity_filter',
                'priority': 'HIGH',
                'recommendation': f"过滤 DEBUG/INFO 级别日志可显著降低成本，占比 {round(debug_info_count/total_count*100, 1)}%",
                'potential_savings': round(potential_savings, 2)
            })
        
        # 3. 保留策略建议
        if stats['estimated_size_gib'] > 100:  # 大于100GB
            storage_savings = stats['estimated_size_gib'] * self.STORAGE_COST_PER_GIB_MONTH * 0.75  # 假设缩短75%保留时间
            recommendations.append({
                'type': 'retention_policy',
                'priority': 'MEDIUM',
                'recommendation': "考虑缩短非生产环境的日志保留期至7-14天",
                'potential_savings': round(storage_savings, 2)
            })
        
        # 4. GKE 特定建议
        gke_cost = cost_df[cost_df['resource_type'].str.contains('k8s', na=False)]['total_cost'].sum()
        if gke_cost > 20:
            recommendations.append({
                'type': 'gke_optimization',
                'priority': 'HIGH',
                'recommendation': f"GKE 日志成本较高 (${gke_cost:.2f})，建议实施健康检查过滤和容器日志优化",
                'potential_savings': round(gke_cost * 0.5, 2)
            })
        
        return recommendations
    
    def create_cost_visualization(self, cost_df: pd.DataFrame, stats: Dict, output_dir: str = "./"):
        """
        创建成本可视化图表
        
        Args:
            cost_df: 成本分析 DataFrame
            stats: 日志量统计
            output_dir: 输出目录
        """
        print("📈 生成成本可视化图表...")
        
        # 设置中文字体
        plt.rcParams['font.sans-serif'] = ['SimHei', 'Arial Unicode MS', 'DejaVu Sans']
        plt.rcParams['axes.unicode_minus'] = False
        
        # 创建子图
        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(15, 12))
        fig.suptitle(f'GCP 日志成本分析报告 - 项目: {self.project_id}', fontsize=16, fontweight='bold')
        
        # 1. 按资源类型的成本分布
        top_resources = cost_df.head(8)
        ax1.pie(top_resources['total_cost'], labels=top_resources['resource_type'], autopct='%1.1f%%')
        ax1.set_title('按资源类型的成本分布')
        
        # 2. 按严重性的日志量分布
        severity_data = pd.Series(stats['by_severity'])
        ax2.bar(severity_data.index, severity_data.values)
        ax2.set_title('按严重性的日志量分布')
        ax2.set_xlabel('严重性级别')
        ax2.set_ylabel('日志条数')
        plt.setp(ax2.xaxis.get_majorticklabels(), rotation=45)
        
        # 3. 每日日志量趋势
        daily_data = pd.Series(stats['by_day']).sort_index()
        ax3.plot(daily_data.index, daily_data.values, marker='o')
        ax3.set_title('每日日志量趋势')
        ax3.set_xlabel('日期')
        ax3.set_ylabel('日志条数')
        plt.setp(ax3.xaxis.get_majorticklabels(), rotation=45)
        
        # 4. 成本构成分析
        total_ingestion = cost_df['ingestion_cost'].sum()
        total_storage = cost_df['storage_cost'].sum()
        cost_breakdown = pd.Series({
            '注入成本': total_ingestion,
            '存储成本': total_storage
        })
        ax4.pie(cost_breakdown.values, labels=cost_breakdown.index, autopct='%1.1f%%')
        ax4.set_title('成本构成分析')
        
        plt.tight_layout()
        
        # 保存图表
        output_path = os.path.join(output_dir, f'gcp_logging_cost_analysis_{self.project_id}.png')
        plt.savefig(output_path, dpi=300, bbox_inches='tight')
        print(f"📊 图表已保存到: {output_path}")
        
        plt.show()
    
    def generate_report(self, days: int = 30, output_dir: str = "./") -> str:
        """
        生成完整的成本分析报告
        
        Args:
            days: 分析天数
            output_dir: 输出目录
            
        Returns:
            报告文件路径
        """
        print("📋 生成完整成本分析报告...")
        
        # 获取数据
        stats = self.get_log_volume_stats(days)
        cost_df = self.analyze_cost_by_resource_type(stats)
        recommendations = self.generate_optimization_recommendations(cost_df, stats)
        
        # 生成报告
        report = {
            'project_id': self.project_id,
            'analysis_period': f'{days} days',
            'generated_at': datetime.utcnow().isoformat(),
            'summary': {
                'total_log_entries': stats['total_entries'],
                'estimated_size_gib': round(stats['estimated_size_gib'], 3),
                'estimated_monthly_cost': round(cost_df['total_cost'].sum(), 2),
                'top_cost_resource': cost_df.iloc[0]['resource_type'] if not cost_df.empty else 'N/A'
            },
            'cost_breakdown': cost_df.to_dict('records'),
            'log_statistics': stats,
            'optimization_recommendations': recommendations,
            'potential_total_savings': round(sum(r.get('potential_savings', 0) for r in recommendations), 2)
        }
        
        # 保存 JSON 报告
        report_path = os.path.join(output_dir, f'gcp_logging_cost_report_{self.project_id}_{datetime.now().strftime("%Y%m%d")}.json')
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        # 生成可视化图表
        if not cost_df.empty:
            self.create_cost_visualization(cost_df, stats, output_dir)
        
        # 打印摘要
        self.print_summary(report)
        
        print(f"📄 完整报告已保存到: {report_path}")
        return report_path
    
    def print_summary(self, report: Dict):
        """打印报告摘要"""
        print("\n" + "="*60)
        print("📊 GCP 日志成本分析摘要")
        print("="*60)
        
        summary = report['summary']
        print(f"项目 ID: {report['project_id']}")
        print(f"分析期间: {report['analysis_period']}")
        print(f"总日志条数: {summary['total_log_entries']:,}")
        print(f"估算大小: {summary['estimated_size_gib']} GiB")
        print(f"估算月成本: ${summary['estimated_monthly_cost']}")
        print(f"主要成本来源: {summary['top_cost_resource']}")
        
        print(f"\n🎯 优化建议数量: {len(report['optimization_recommendations'])}")
        print(f"💰 潜在总节省: ${report['potential_total_savings']}")
        
        print("\n📋 主要建议:")
        for i, rec in enumerate(report['optimization_recommendations'][:3], 1):
            print(f"{i}. [{rec['priority']}] {rec['recommendation']}")
            if 'potential_savings' in rec:
                print(f"   💰 潜在节省: ${rec['potential_savings']}")
        
        print("="*60)

def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='GCP 日志成本分析工具')
    parser.add_argument('project_id', help='GCP 项目 ID')
    parser.add_argument('--days', type=int, default=30, help='分析天数 (默认: 30)')
    parser.add_argument('--credentials', help='服务账号密钥文件路径')
    parser.add_argument('--output-dir', default='./', help='输出目录 (默认: 当前目录)')
    
    args = parser.parse_args()
    
    try:
        # 创建分析器
        analyzer = GCPLoggingCostAnalyzer(args.project_id, args.credentials)
        
        # 生成报告
        report_path = analyzer.generate_report(args.days, args.output_dir)
        
        print(f"\n✅ 分析完成！报告已保存到: {report_path}")
        
    except Exception as e:
        print(f"❌ 分析过程中出错: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()