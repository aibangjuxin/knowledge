# Parent POM Dependency Version Conflict Debugging Guide

## Problem Scenario

When your project does not directly specify the Spring Boot version in `<dependencies>`, but instead defines the version through the parent POM's `<properties>` section:

```xml
<!-- In parent POM -->
<properties>
    <springboot.version>2.7.10</springboot.version>
</properties>
```

But the runtime still loads the wrong version (such as 2.6.6), indicating that **there is a version conflict at the parent POM level**.

---

## Core Problem Analysis

### 1. Parent POM Inheritance Chain Issues
- Your project inherits from a parent POM
- That parent POM may inherit from another parent POM (such as a corporate-level parent POM)
- An older version is forced at some level in the multi-level inheritance

### 2. Properties Priority Issues
- Maven resolves properties in a specific order: command line > internal POM > parent POM
- If there's a higher priority property definition in the parent POM, it will override your settings

### 3. BOM (Bill of Materials) Import Order
- Multiple BOMs may be imported, with later imports overriding earlier ones
- Version management in BOMs takes precedence over versions in properties

---

## Debugging Steps

### Step 1: Analyze the Complete POM Inheritance Chain
```bash
mvn help:effective-pom -Doutput=effective-pom.xml
```
- Look for `<parent>` tags to trace the complete inheritance chain
- Check version definitions in each parent POM

### Step 2: Check All Properties Definitions
```bash
mvn help:effective-pom | grep -A 5 -B 5 "springboot.version"
```
- Find all `springboot.version` definition locations
- Determine which definition takes effect

### Step 3: Analyze Dependency Management Section
```bash
mvn help:effective-pom | grep -A 50 -B 10 "dependencyManagement"
```
- Find all imported BOMs
- Confirm BOM import order and versions

### Step 4: Detailed Dependency Tree Analysis
```bash
mvn dependency:tree -Dverbose -Dincludes=org.springframework.boot
```
- View specific version conflict information
- Identify which dependency causes the old version to be introduced

---

## Common Parent POM Problem Patterns

### Pattern 1: Corporate Parent POM Override
```xml
<!-- Your POM -->
<parent>
    <groupId>com.company</groupId>
    <artifactId>company-parent</artifactId>
    <version>1.0</version>
</parent>

<properties>
    <springboot.version>2.7.10</springboot.version>  <!-- May be overridden -->
</properties>
```

**Solution**: Redefine the property in your POM, or force the version in `<dependencyManagement>`.

### Pattern 2: Multiple BOM Conflicts
```xml
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>2.7.10</version>  <!-- Expected version -->
            <type>pom</type>
            <scope>import</scope>
        </dependency>
        <!-- Another BOM may override the above version -->
    </dependencies>
</dependencyManagement>
```

**Solution**: Ensure your BOM import comes before other BOMs, or use more specific version management.

### Pattern 3: Plugin Version Mismatch with Dependency Version
```xml
<properties>
    <springboot.version>2.7.10</springboot.version>
</properties>

<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <!-- If plugin version doesn't match dependency version, it may cause issues -->
        </plugin>
    </plugins>
</build>
```

---

## Solutions

### Solution 1: Force Property Value in Your POM
```xml
<properties>
    <springboot.version>2.7.10</springboot.version>
</properties>

<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>${springboot.version}</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>
```

### Solution 2: Exclude Conflicting Dependencies from Parent POM
```xml
<dependencyManagement>
    <dependencies>
        <!-- First import the BOM you want -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-dependencies</artifactId>
            <version>2.7.10</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
        <!-- Then exclude conflicting BOMs from parent POM -->
    </dependencies>
</dependencyManagement>
```

### Solution 3: Use Maven Enforcer Plugin to Check Versions
```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <version>3.0.0-M3</version>
    <executions>
        <execution>
            <id>enforce-versions</id>
            <goals>
                <goal>enforce</goal>
            </goals>
            <configuration>
                <rules>
                    <requireMavenVersion>
                        <version>3.6.0</version>
                    </requireMavenVersion>
                    <bannedDependencies>
                        <excludes>
                            <exclude>org.springframework.boot:spring-boot:*2.6.*</exclude>
                        </excludes>
                    </bannedDependencies>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

---

## Verification Steps

### 1. Verify Property Value
```bash
mvn help:evaluate -Dexpression=springboot.version -q -DforceStdout
```

### 2. Verify Dependency Versions
```bash
mvn dependency:list | grep spring-boot
```

### 3. Verify Build Plugin Versions
```bash
mvn help:effective-pom | grep -A 10 -B 10 "spring-boot-maven-plugin"
```

---

## CI/CD Integration Verification

Add verification steps to your CI pipeline:

```bash
# Verify property value
echo "Checking springboot.version property..."
ACTUAL_VERSION=$(mvn help:evaluate -Dexpression=springboot.version -q -DforceStdout)
if [ "$ACTUAL_VERSION" != "2.7.10" ]; then
    echo "ERROR: Expected springboot.version 2.7.10, but got $ACTUAL_VERSION"
    exit 1
fi

# Verify no conflicting versions in dependency tree
if mvn dependency:tree | grep -q "spring-boot.*2.6"; then
    echo "ERROR: Found spring-boot 2.6.x in dependency tree"
    exit 1
fi

echo "Version validation passed"
```

---

## Best Practices

1. **Explicitly declare dependency management**: Even when using parent POMs, explicitly declare version management for key dependencies in subprojects
2. **Use BOM for version control**: Manage versions uniformly through `dependencyManagement` and BOM
3. **Regularly review inheritance chain**: Regularly check parent POM changes to ensure old versions aren't accidentally introduced
4. **Implement version verification**: Add version verification steps during the build process to detect issues early