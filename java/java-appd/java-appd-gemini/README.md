# Java AppDynamics Memory Analysis Guide

This documentation set is generated to help you analyze and distinguish the memory usage of your Java Spring Boot application and the AppDynamics (AppD) Agent.

## Context
You are deploying Java applications where the AppD Agent is injected via an Init Container. You need to know:
1. How much memory the AppD Agent consumes.
2. How much memory the Spring Boot application consumes.
3. How to use Docker Hub tools and Sidecars to analyze this.

## Documentation Contents

### 1. [Memory Analysis Methodology](./memory-analysis-guide.md)
**Core Solution**: Explains how to use JVM Native Memory Tracking (NMT) to strictly distinguish between "App Memory" and "Agent Memory". Since the Agent runs inside the JVM process, standard container metrics (`docker stats`) cannot distinguish them.

### 2. [Sidecar Profiling Strategy](./sidecar-profiling.md)
**Implementation**: A practical guide on how to attach a Sidecar to your running Pods to perform this analysis without installing tools in your production images. Covers `kubectl debug`, `shareProcessNamespace`, and permission handling.

### 3. [Docker Hub Tools](./docker-hub-tools.md)
**Toolbox**: A curated list of ready-to-use Docker images from Docker Hub that contain the necessary profiling tools (`jcmd`, `jmap`, `MAT`, etc.) for your Sidecar.

---

## Quick Start Summary

1. **Enable NMT**: Add `-XX:NativeMemoryTracking=detail` to your Java startup options.
2. **Launch Sidecar**: Use `kubectl debug` with an OpenJDK image.
3. **Analyze**: Run `jcmd <pid> VM.native_memory summary` inside the sidecar.
