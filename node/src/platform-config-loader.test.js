/**
 * 平台配置加载器单元测试
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const {
    PlatformConfig,
    loadProperties,
    expandEnvVars
} = require('./platform-config-loader');

describe('PlatformConfig', () => {
    describe('validate', () => {
        test('should pass validation with valid config', () => {
            const config = new PlatformConfig();
            const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-'));
            
            // 创建临时证书文件
            fs.writeFileSync(path.join(tmpDir, 'tls.crt'), 'test cert');
            fs.writeFileSync(path.join(tmpDir, 'tls.key'), 'test key');
            
            config.port = '8443';
            config.sslEnabled = true;
            config.certPath = path.join(tmpDir, 'tls.crt');
            config.keyPath = path.join(tmpDir, 'tls.key');

            expect(() => config.validate()).not.toThrow();

            // 清理
            fs.rmSync(tmpDir, { recursive: true });
        });

        test('should fail validation when port is missing', () => {
            const config = new PlatformConfig();
            config.port = '';

            expect(() => config.validate()).toThrow('Port is required');
        });

        test('should fail validation when SSL is enabled but cert is missing', () => {
            const config = new PlatformConfig();
            config.port = '8443';
            config.sslEnabled = true;
            config.certPath = '';

            expect(() => config.validate()).toThrow('Cert path is required');
        });

        test('should fail validation when cert file does not exist', () => {
            const config = new PlatformConfig();
            config.port = '8443';
            config.sslEnabled = true;
            config.certPath = '/nonexistent/cert.crt';
            config.keyPath = '/nonexistent/key.key';

            expect(() => config.validate()).toThrow('Cert file not found');
        });
    });

    describe('toString', () => {
        test('should return JSON string representation', () => {
            const config = new PlatformConfig();
            config.port = '8443';
            config.contextPath = '/api/v1';

            const str = config.toString();
            expect(str).toContain('8443');
            expect(str).toContain('/api/v1');
        });
    });
});

describe('loadProperties', () => {
    test('should load properties from file', () => {
        const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-'));
        const configFile = path.join(tmpDir, 'test.properties');

        const content = `# Test config
server.port=8443
server.ssl.enabled=true
server.context-path=/api/v1

# Comment line
empty.value=
`;
        fs.writeFileSync(configFile, content);

        const props = loadProperties(configFile);

        expect(props['server.port']).toBe('8443');
        expect(props['server.ssl.enabled']).toBe('true');
        expect(props['server.context-path']).toBe('/api/v1');
        expect(props['empty.value']).toBe('');

        // 清理
        fs.rmSync(tmpDir, { recursive: true });
    });

    test('should skip comments and empty lines', () => {
        const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'test-'));
        const configFile = path.join(tmpDir, 'test.properties');

        const content = `
# This is a comment
server.port=8443

# Another comment
server.ssl.enabled=true
`;
        fs.writeFileSync(configFile, content);

        const props = loadProperties(configFile);

        expect(Object.keys(props).length).toBe(2);
        expect(props['server.port']).toBe('8443');
        expect(props['server.ssl.enabled']).toBe('true');

        // 清理
        fs.rmSync(tmpDir, { recursive: true });
    });
});

describe('expandEnvVars', () => {
    beforeEach(() => {
        process.env.TEST_API = 'user-service';
        process.env.TEST_VERSION = '1';
    });

    afterEach(() => {
        delete process.env.TEST_API;
        delete process.env.TEST_VERSION;
    });

    test('should expand environment variables', () => {
        const input = '/${TEST_API}/v${TEST_VERSION}';
        const result = expandEnvVars(input);
        expect(result).toBe('/user-service/v1');
    });

    test('should handle string without variables', () => {
        const input = '/api/v1';
        const result = expandEnvVars(input);
        expect(result).toBe('/api/v1');
    });

    test('should handle single variable', () => {
        const input = '${TEST_API}';
        const result = expandEnvVars(input);
        expect(result).toBe('user-service');
    });

    test('should handle multiple variables', () => {
        const input = 'prefix-${TEST_API}-${TEST_VERSION}-suffix';
        const result = expandEnvVars(input);
        expect(result).toBe('prefix-user-service-1-suffix');
    });

    test('should handle nonexistent variables', () => {
        const input = '${NONEXISTENT}';
        const result = expandEnvVars(input);
        expect(result).toBe('');
    });
});
