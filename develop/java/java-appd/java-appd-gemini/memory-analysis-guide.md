# Memory Analysis Methodology: AppD vs Spring Boot

## The Challenge
In your environment, AppDynamics is injected via an Init Container and attached using `-javaagent`.
*   **Process View**: The Agent runs *inside* the Java process.
*   **Container View**: `docker stats` or `kubectl top` shows the **Total Memory** (JVM Heap + Metaspace + Thread Stacks + Agent Overhead + Native Code).
*   **Problem**: You cannot distinguish "App Memory" from "Agent Memory" using external tools.

## The Solution: Native Memory Tracking (NMT)
The only way to strictly distinguish them is to ask the JVM itself how it is using memory. **Native Memory Tracking (NMT)** is a JVM feature that tracks internal memory usage.

### Step 1: Enable NMT
You must modify your Java startup options (usually in your Deployment YAML or `JAVA_TOOL_OPTIONS`).

```yaml
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:NativeMemoryTracking=detail -XX:+UnlockDiagnosticVMOptions -XX:+PrintNMTStatistics"
```

*   `detail`: Tracks memory by call site (needed to see Agent specifics).
*   `UnlockDiagnosticVMOptions`: Enables advanced options.
*   `PrintNMTStatistics`: Prints a summary on exit (optional but useful).

### Step 2: Restart the Pod
Apply the changes and restart your Pod. NMT adds a small overhead (5-10%), so it is recommended for debugging/staging, or controlled production sampling.

### Step 3: Capture the Baseline (Without Agent) - *Optional but Recommended*
To get the most accurate "Cost of Agent" number:
1.  Deploy your app **without** the AppD `-javaagent` argument.
2.  Run `jcmd <pid> VM.native_memory summary`.
3.  Record the "Total" committed memory.

### Step 4: Capture with Agent
1.  Deploy your app **with** the AppD `-javaagent`.
2.  Run `jcmd <pid> VM.native_memory summary`.

### Step 5: Analyze the Output
Run the command (via Sidecar, see [Sidecar Profiling Strategy](./sidecar-profiling.md)):
```bash
jcmd 1 VM.native_memory summary
```

#### Sample Output Breakdown
```text
Total: reserved=4GB, committed=2.5GB  <-- Total Process Memory

-                 Java Heap (reserved=2GB, committed=2GB)
                            (mmap: reserved=2GB, committed=2GB)

-                     Class (reserved=1GB, committed=128MB)
                            (classes #10543)
                            (malloc=2MB #12000)
                            (mmap: reserved=1GB, committed=126MB)

-                    Thread (reserved=200MB, committed=200MB)
                            (thread #200)
                            (stack: reserved=198MB, committed=198MB)

-          AppDynamicsAgent (reserved=150MB, committed=150MB)  <-- LOOK FOR THIS
                            (malloc=50MB)
                            (mmap: reserved=100MB, committed=100MB)

-                  Internal (reserved=50MB, committed=50MB)
                            (malloc=50MB)
```

### How to Calculate
1.  **AppD Memory**: Look for a specific section named `AppDynamicsAgent` (if the agent registers itself to NMT) or look for increases in:
    *   **Internal**: AppD often uses native memory here.
    *   **Symbol**: Agent adds many symbols.
    *   **Class**: Agent instrumentation generates new classes (proxies).
    *   **Metaspace**: This is the biggest hidden cost. The Agent loads thousands of helper classes.

**Formula**:
`AppD Impact` ≈ `(Metaspace_With_Agent - Metaspace_Baseline)` + `Native_Agent_Overhead`

*Note: If AppD doesn't show up as a named section, the "Baseline vs With-Agent" comparison is the only 100% accurate method.*
