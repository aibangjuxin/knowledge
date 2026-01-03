/**
 * 平台配置加载器 - Node.js 版本
 * 用于读取平台注入的 ConfigMap 配置
 */

const fs = require('fs');
const path = require('path');

/**
 * 平台配置类
 */
class PlatformConfig {
    constructor() {
        this.port = '8443';
        this.sslEnabled = true;
        this.certPath = '/opt/keystore/tls.crt';
        this.keyPath = '/opt/keystore/tls.key';
        this.contextPath = '/';
    }

    /**
     * 验证配置
     */
    validate() {
        if (!this.port) {
            throw new Error('Port is required');
        }

        if (this.sslEnabled) {
            if (!this.certPath) {
                throw new Error('Cert path is required when SSL is enabled');
            }
            if (!this.keyPath) {
                throw new Error('Key path is required when SSL is enabled');
            }

            // 检查证书文件是否存在
            if (!fs.existsSync(this.certPath)) {
                throw new Error(`Cert file not found: ${this.certPath}`);
            }
            if (!fs.existsSync(this.keyPath)) {
                throw new Error(`Key file not found: ${this.keyPath}`);
            }
        }
    }

    /**
     * 返回配置的字符串表示
     */
    toString() {
        return JSON.stringify({
            port: this.port,
            sslEnabled: this.sslEnabled,
            contextPath: this.contextPath,
            certPath: this.certPath,
            keyPath: this.keyPath
        }, null, 2);
    }
}

/**
 * 读取 Java properties 格式文件
 * @param {string} filePath - 配置文件路径
 * @returns {Object} 配置键值对
 */
function loadProperties(filePath) {
    const content = fs.readFileSync(filePath, 'utf-8');
    const props = {};

    content.split('\n').forEach(line => {
        line = line.trim();

        // 跳过注释和空行
        if (!line || line.startsWith('#')) {
            return;
        }

        // 解析 key=value
        const index = line.indexOf('=');
        if (index > 0) {
            const key = line.substring(0, index).trim();
            const value = line.substring(index + 1).trim();
            props[key] = value;
        }
    });

    return props;
}

/**
 * 获取配置值，支持默认值
 * @param {Object} props - 配置对象
 * @param {string} key - 配置键
 * @param {string} defaultValue - 默认值
 * @returns {string} 配置值
 */
function getProperty(props, key, defaultValue) {
    return props[key] !== undefined ? props[key] : defaultValue;
}

/**
 * 替换字符串中的环境变量占位符
 * 支持 ${VAR_NAME} 格式
 * @param {string} str - 输入字符串
 * @returns {string} 替换后的字符串
 */
function expandEnvVars(str) {
    let result = str;

    // 查找所有 ${...} 占位符
    const regex = /\$\{([^}]+)\}/g;
    let match;

    while ((match = regex.exec(str)) !== null) {
        const varName = match[1];
        const varValue = process.env[varName] || '';
        result = result.replace(match[0], varValue);
    }

    return result;
}

/**
 * 从平台注入的配置文件加载配置
 * 默认读取 /opt/config/server-conf.properties
 * @returns {Promise<PlatformConfig>} 平台配置对象
 */
async function loadPlatformConfig() {
    const configPath = process.env.PLATFORM_CONFIG_PATH || '/opt/config/server-conf.properties';

    try {
        const props = loadProperties(configPath);
        const config = new PlatformConfig();

        // 读取配置
        config.port = getProperty(props, 'server.port', '8443');
        config.sslEnabled = getProperty(props, 'server.ssl.enabled', 'true') === 'true';
        
        // Node.js 使用 PEM 格式证书
        config.certPath = getProperty(props, 'server.ssl.cert-path', '/opt/keystore/tls.crt');
        config.keyPath = getProperty(props, 'server.ssl.key-path', '/opt/keystore/tls.key');
        
        // Context Path
        config.contextPath = getProperty(props, 'server.context-path', '/');

        // 如果没有配置 context-path，尝试读取其他可能的键
        if (config.contextPath === '/') {
            config.contextPath = getProperty(props, 'server.servlet.context-path', '/');
        }

        // 替换环境变量占位符
        config.contextPath = expandEnvVars(config.contextPath);

        // 验证配置
        config.validate();

        return config;
    } catch (error) {
        throw new Error(`Failed to load platform config: ${error.message}`);
    }
}

/**
 * 从平台注入的配置文件加载配置（简化版 - 用于独立 ConfigMap）
 * @returns {Promise<PlatformConfig>} 平台配置对象
 */
async function loadPlatformConfigSimple() {
    const configPath = process.env.PLATFORM_CONFIG_PATH || '/opt/config/server-conf.properties';

    try {
        const props = loadProperties(configPath);
        const config = new PlatformConfig();

        config.port = getProperty(props, 'server.port', '8443');
        config.sslEnabled = getProperty(props, 'server.ssl.enabled', 'true') === 'true';
        config.certPath = getProperty(props, 'server.ssl.cert-path', '/opt/keystore/tls.crt');
        config.keyPath = getProperty(props, 'server.ssl.key-path', '/opt/keystore/tls.key');
        config.contextPath = getProperty(props, 'server.context-path', '/');

        // 替换环境变量占位符
        config.contextPath = expandEnvVars(config.contextPath);

        // 验证配置
        config.validate();

        return config;
    } catch (error) {
        throw new Error(`Failed to load platform config: ${error.message}`);
    }
}

module.exports = {
    PlatformConfig,
    loadPlatformConfig,
    loadPlatformConfigSimple,
    loadProperties,
    expandEnvVars
};
