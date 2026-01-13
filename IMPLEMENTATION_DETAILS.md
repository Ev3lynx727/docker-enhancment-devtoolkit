# Implementation Details for main.go

## Overview

This document provides implementation details for all stub functions in `main.go`.

## Functions to Implement

### 1. loadConfig()

**Purpose:** Parse command-line flags and load .env file

**Implementation:**
```go
func loadConfig() (*Config, error) {
    // Parse command-line flags
    flag.Parse()

    // Load .env file
    if _, err := os.ReadFile(config.EnvFile); err == nil {
        export $(grep -v '^#' config.EnvFile | xargs)
    }

    // Set default paths
    if config.WorkDir == "" {
        dir, err := os.Getwd()
        if err != nil {
            return nil, err
        }
        config.WorkDir = dir
    }

    // Set default script paths (all centralized in script/)
    scriptDir := filepath.Join(dir, "script")
    config.ScriptDir = scriptDir
    config.AuthScript = filepath.Join(scriptDir, "loginall.sh")
    config.LogoutScript = filepath.Join(scriptDir, "logoutall.sh")
    config.DockerScript = filepath.Join(scriptDir, "enhancment-docker-builder.sh")
    config.RestoreScript = filepath.Join(scriptDir, "restore-default-config.sh")

    // Set default values
    if config.Logout {
        config.SkipAuth = true
        config.SkipDocker = true
        config.SkipVerify = true
    }

    // Validate required fields
    if !config.SkipAuth {
        if config.GitHubUsername == "" || config.GitHubToken == "" {
            return nil, errors.New("GITHUB_USERNAME and GITHUB_TOKEN required")
        }
    }

    return config, nil
}
```

---

### 2. executeScript()

**Purpose:** Execute shell script with output streaming and logging

**Implementation:**
```go
func executeScript(ctx context.Context, scriptPath string, env []string, verbose bool, logFile *os.File) (*PhaseResult, error) {
    startTime := time.Now()

    // Check if script exists
    if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
        return nil, fmt.Errorf("script not found: %s", scriptPath)
    }

    // Create command
    cmd := exec.CommandContext(ctx, "bash", append([]string{scriptPath}))

    // Setup environment
    if len(env) > 0 {
        cmd.Env = append(os.Environ(), env...)
    }

    // Setup output
    var stdout, stderr strings.Builder
    if verbose {
        cmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
        cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
    }

    // Log output
    if logFile != nil {
        cmd.Stdout = io.MultiWriter(cmd.Stdout, logFile)
        cmd.Stderr = io.MultiWriter(cmd.Stderr, logFile)
    }

    // Execute
    err := cmd.Run()
    duration := time.Since(startTime)

    result := &PhaseResult{
        Script:   scriptPath,
        Success:  err == nil,
        Duration: duration,
        Output:   stdout.String() + "\n" + stderr.String(),
    }

    return result, err
}
```

---

### 3. autoRestartDocker()

**Purpose:** Restart Docker daemon with graceful wait

**Implementation:**
```go
func autoRestartDocker(ctx context.Context, verbose bool) error {
    fmt.Println("Restarting Docker daemon...")

    // Stop Docker
    stopCmd := exec.CommandContext(ctx, "sudo", "systemctl", "stop", "docker.service")
    if verbose {
        stopCmd.Stdout = os.Stdout
        stopCmd.Stderr = os.Stderr
    }
    if err := stopCmd.Run(); err != nil {
        return err
    }

    // Wait
    time.Sleep(2 * time.Second)

    // Start Docker
    startCmd := exec.CommandContext(ctx, "sudo", "systemctl", "start", "docker.service")
    if verbose {
        startCmd.Stdout = os.Stdout
        startCmd.Stderr = os.Stderr
    }
    err := startCmd.Run()
    if err != nil {
        return err
    }

    // Wait for Docker to be ready
    maxWait := 30 * time.Second
    checkInterval := 1 * time.Second
    elapsed := 0 * time.Second

    for elapsed < maxWait {
        time.Sleep(checkInterval)
        checkCmd := exec.CommandContext(ctx, "docker", "info")
        if checkCmd.Run() == nil {
            if verbose {
                fmt.Println("Docker daemon is ready")
            }
            return nil
        }
        elapsed += checkInterval
    }

    if verbose {
        fmt.Println("Docker daemon ready after checking")
    }

    return nil
}
```

---

### 4. verifySetup()

**Purpose:** Verify Docker daemon and GHCR authentication

**Implementation:**
```go
func verifySetup(ctx context.Context, config *Config) (*VerificationResult, error) {
    result := &VerificationResult{
        Details: []string{},
        Errors: []string{},
        DockerRunning: false,
        GHCRAuthenticated: false,
    ConfigApplied: false,
    }

    // Check Docker daemon
    dockerInfoCmd := exec.Command("docker", "info", "--format", "{{json .}}")
    output, err := dockerInfoCmd.CombinedOutput()
    if err != nil {
        result.Errors = append(result.Errors, "Docker daemon not running: "+err.Error())
    } else {
        result.Details = append(result.Details, "Docker daemon is running")
        result.DockerRunning = true
    }

    // Check GHCR authentication
    dockerConfigPath := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
    data, err := os.ReadFile(dockerConfigPath)
    if err == nil {
        var dockerConfig map[string]interface{}
        json.Unmarshal(data, &dockerConfig)
        if auths, ok := dockerConfig["auths"].(map[string]interface{}); ok {
            if ghcrIO, ok := auths["ghcr.io"].(string); ok && ghcrIO != nil {
                result.Details = append(result.Details, "GHCR authenticated")
                result.GHCRAuthenticated = true
            } else {
                result.Errors = append(result.Errors, "GHCR not authenticated")
            }
        }
    }

    // Verify configuration
    if result.DockerRunning {
        result.ConfigApplied = true
    }

    return result, nil
}
```

---

### 5. printSummary()

**Purpose:** Print final summary report

**Implementation:**
```go
func printSummary(results []*PhaseResult, verification *VerificationResult) {
    fmt.Println()
    fmt.Println("========================================")
    fmt.Println("Setup Summary")
    fmt.Println("========================================")
    fmt.Println()

    fmt.Println("Phases Executed:")
    for i, result := range results {
        if result.Success {
            fmt.Printf("  ✓ %s\n", result.Name)
        } else {
            fmt.Printf("  ✗ %s\n", result.Name)
        }
    }

    if verification != nil {
        fmt.Println()
        fmt.Println("Verification Status:")
        for _, detail := range verification.Details {
            fmt.Printf("  %s\n", detail)
        }
        for _, err := range verification.Errors {
            fmt.Printf("  %s\n", err)
        }
    }

    allSuccess := true
    for _, result := range results {
        if !result.Success {
            allSuccess = false
            break
        }
    }

    if allSuccess {
        printBanner()
    } else {
        printFailureBanner()
    }
}

func printBanner() {
    fmt.Println()
    fmt.Println("╔═════════════════════════════════════════╗")
    fmt.Println("║              ✓ SETUP COMPLETE - SUCCESS                  ║")
    fmt.Println("╚═════════════════════════════════════╝")
    fmt.Println()
}

func printFailureBanner() {
    fmt.Println()
    fmt.Println("╔═══════════════════════════════════════╗")
    fmt.Println("║              ✗ SETUP INCOMPLETE - CHECK ERRORS           ║")
    fmt.Println("╚═════════════════════════════════════════╝")
    fmt.Println()
}
```

---

## VerificationResult Type

Update to use:

```go
type VerificationResult struct {
    DockerRunning    bool
    GHCRAuthenticated bool
    ConfigApplied    bool
    Details       []string
    Errors        []string
}
```

---

## Usage Examples

### Load Config
```go
config, err := loadConfig()
if err != nil {
    log.Fatal(err)
}
```

### Execute Script
```go
result, err := executeScript(ctx, config.AuthScript, nil, config.Verbose, logFile)
if err != nil {
    log.Fatal(err)
}
```

### Restart Docker
```go
err := autoRestartDocker(ctx, config.Verbose)
if err != nil {
    log.Fatal(err)
}
```

### Verify Setup
```go
verification, err := verifySetup(ctx, &config)
if err != nil {
    log.Fatal(err)
}
```

---

## Next Steps

1. Add these implementations to `main.go`
2. Remove stub functions (`TODO: Implement these functions`)
3. Update `Config` struct to add `VerificationResult` fields
4. Test full workflow

---

**Version:** 3.0
**Last Updated:** 2025-01-12
