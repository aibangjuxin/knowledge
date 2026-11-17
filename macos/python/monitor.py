import psutil
import socket
import time
from collections import defaultdict

class ConnectionMonitor:
    def __init__(self):
        self.connections_history = defaultdict(list)
    
    def get_active_connections(self):
        """获取当前活跃连接"""
        connections = []
        for conn in psutil.net_connections(kind='inet'):
            if conn.status == 'ESTABLISHED':
                try:
                    # 获取进程信息
                    process = psutil.Process(conn.pid) if conn.pid else None
                    process_name = process.name() if process else "Unknown"
                    
                    # 反向DNS解析
                    try:
                        hostname = socket.gethostbyaddr(conn.raddr.ip)[0]
                    except:
                        hostname = conn.raddr.ip
                    
                    connection_info = {
                        'local_addr': f"{conn.laddr.ip}:{conn.laddr.port}",
                        'remote_addr': f"{conn.raddr.ip}:{conn.raddr.port}",
                        'hostname': hostname,
                        'process': process_name,
                        'pid': conn.pid,
                        'timestamp': time.time()
                    }
                    connections.append(connection_info)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
        
        return connections
    
    def monitor_realtime(self, interval=2):
        """实时监控连接"""
        print("Real-time Connection Monitor Started...")
        print("-" * 80)
        
        while True:
            try:
                connections = self.get_active_connections()
                
                # 清屏并显示当前连接
                print(f"\033[2J\033[H")  # 清屏
                print(f"Active Connections ({len(connections)}) - {time.strftime('%Y-%m-%d %H:%M:%S')}")
                print("-" * 80)
                
                for conn in connections:
                    print(f"Process: {conn['process']:15} | "
                          f"Remote: {conn['hostname']:30} | "
                          f"IP: {conn['remote_addr']:20}")
                
                time.sleep(interval)
                
            except KeyboardInterrupt:
                print("\nMonitoring stopped.")
                break

# 使用示例
if __name__ == "__main__":
    monitor = ConnectionMonitor()
    monitor.monitor_realtime()
