package com.company.maxcompute;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
    "maxcompute.access.id=test-id",
    "maxcompute.access.key=test-key",
    "maxcompute.project=test-project",
    "maxcompute.endpoint=http://test-endpoint"
})
class MaxComputeHealthCheckApplicationTests {

    @Test
    void contextLoads() {
        // 测试应用上下文是否能正常加载
    }
}