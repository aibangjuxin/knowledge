# Docker Hub Tools for Java Memory Analysis

You asked for tools available on Docker Hub to analyze Java memory. Here are the best images to use as Sidecars.

## 1. Standard JDK Images (The "Swiss Army Knife")
Most of the time, the standard JDK contains everything you need (`jcmd`, `jmap`, `jstack`, `jstat`).

*   **Image**: `openjdk:17-jdk-slim` (or `openjdk:11-jdk-slim`, `openjdk:8-jdk-alpine`)
*   **Size**: ~200MB
*   **Tools Included**:
    *   `jcmd`: Native Memory Tracking (NMT), Flight Recorder controls.
    *   `jmap`: Heap dumps (`jmap -dump:format=b,file=heap.bin <pid>`).
    *   `jstack`: Thread dumps.
*   **Best For**: General purpose debugging and NMT analysis.

## 2. Eclipse Memory Analyzer (MAT)
For deep heap analysis (finding memory leaks), you usually dump the heap and analyze it offline. However, some images allow running headless analysis.

*   **Image**: `eclipse/mat` (Unofficial builds often exist, or build your own)
*   **Note**: It is usually better to `jmap` the dump to a Persistent Volume, then download it to your laptop to analyze with the MAT GUI.
*   **Best For**: Analyzing *why* the Heap is full, not for NMT/Native memory.

## 3. Async Profiler
The best low-overhead profiler for CPU and Memory allocation.

*   **Image**: `ghcr.io/jvm-profiling-tools/async-profiler` (or similar community images)
*   **Command**: `./profiler.sh -d 30 -e alloc -f /tmp/flamegraph.html <pid>`
*   **Best For**: Seeing *where* in the code memory is being allocated (Flamegraphs).

## 4. JMX Exporter (Prometheus)
If you want to monitor memory over time in Grafana.

*   **Image**: `bitnami/jmx-exporter`
*   **Usage**: Run as a sidecar, expose port, and scrape with Prometheus.
*   **Metrics**:
    *   `jvm_memory_bytes_used` (Heap vs Non-Heap)
    *   `jvm_memory_pool_bytes_used` (Metaspace, Code Cache, etc.)
*   **Best For**: Long-term trending. You can see if "Non-Heap" grows when AppD is enabled.

## 5. Arthas (Alibaba)
A powerful interactive Java diagnostic tool.

*   **Image**: `arthas/arthas`
*   **Usage**: Attach to the process and run commands like `dashboard`, `memory`, `vmtool`.
*   **Best For**: Interactive troubleshooting without complex setup.

---

## Recommendation for Your Case
Since you want to distinguish **AppD vs App Memory**:

1.  **Primary Tool**: `openjdk:17-jdk-slim`
    *   Use `jcmd <pid> VM.native_memory summary`.
    *   This is the only tool that gives the breakdown needed to see Agent overhead.

2.  **Secondary Tool**: `bitnami/jmx-exporter`
    *   Use this to graph `Metaspace` usage over time. AppD consumes a lot of Metaspace (loading classes).
