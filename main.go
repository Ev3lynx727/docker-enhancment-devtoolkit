// =============================================================================
// DevOps Setup Orchestration Script - v3.0
// =============================================================================
// This Go script orchestrates to complete DevOps setup workflow:
// 1. Phase 1: Authentication Setup (setup-account/loginall.sh)
// 2. Phase 2: Docker Daemon Configuration (script/enhancment-docker-builder.sh)
// 3. Phase 3: Verification
//
// Or:
//   go run main.go --logout            # Logout from all registries
//
// Usage:
//   go run main.go                    # Run all phases
//   go run main.go --skip-auth        # Skip authentication
//   go run main.go --skip-docker      # Skip Docker config
//   go run main.go --logout           # Logout from all accounts
//   go run main.go --clean-cache      # Logout + clean build cache
//   go run main.go --clean-all        # Logout + clean everything
//   go run main.go --dry-run          # Show commands without executing
//   sudo go run main.go               # Auto-restart Docker (requires sudo)
//
// See: implement-with-go.md for complete implementation details
//
// Version: 3.0
// Last Updated: 2025-01-12
// =============================================================================
// This Go script orchestrates the complete DevOps setup workflow:
// 1. Phase 1: Authentication Setup (setup-account/loginall.sh)
// 2. Phase 2: Docker Daemon Configuration (script/enhancment-docker-builder.sh)
// 3. Phase 3: Verification
//
// Or:
//   go run main.go --logout            # Logout from all registries
//
// Usage:
//   go run main.go                    # Run all phases
//   go run main.go --skip-auth        # Skip authentication
//   go run main.go --skip-docker      # Skip Docker config
//   go run main.go --logout           # Logout from all accounts
//   go run main.go --dry-run          # Show commands without executing
//   sudo go run main.go               # Auto-restart Docker (requires sudo)
//
// See: implement-with-go.md for complete implementation details
// =============================================================================

package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Configuration represents the orchestration configuration
type Config struct {
	// Paths
	WorkDir string
	EnvFile string
	LogDir  string

	// Scripts
	ScriptDir        string
	AuthScript       string
	LogoutScript     string
	DockerScript     string
	RestoreScript    string
	DockerScriptArgs []string

	// Flags
	Logout     bool
	CleanCache bool
	CleanGhCli bool
	CleanAll   bool
	Force      bool
	SkipAuth   bool
	SkipDocker bool
	SkipVerify bool
	Verbose    bool
	DryRun     bool

	// Behavior
	AutoRestartDocker bool

	// Environment
	GitHubUsername string
	GitHubToken    string
	DockerUsername string
	DockerPassword string

	// Webhook (optional)
	WebhookEnabled bool
	WebhookPort    int
	WebhookSecret  string
}

// PhaseResult represents the result of executing a phase
type PhaseResult struct {
	Name     string
	Script   string
	Success  bool
	Output   string
	Error    error
	Duration time.Duration
}

// =============================================================================
// Main Entry Point
// =============================================================================

func main() {
	fmt.Println("DevOps Setup Orchestration - Go Implementation")
	fmt.Println("==============================================")
	fmt.Println()

	config, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(4)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\n\nSetup interrupted by user")
		cancel()
	}()

	logFile, err := setupLogging(config.LogDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to setup logging: %v\n", err)
	}
	if logFile != nil {
		defer logFile.Close()
		logFile.WriteString(fmt.Sprintf("[%s] Starting DevOps setup orchestration\n",
			time.Now().Format("2006-01-02 15:04:05")))
	}

	var results []*PhaseResult
	phaseNum := 0
	totalPhases := 3

	if config.Logout {
		printPhaseHeader(1, 1, "Logout All Accounts")
		result := executeLogoutPhase(ctx, config, logFile)
		printPhaseResult(result)

		if result.Success {
			printLogoutSummary(logFile)
		}
		return
	}

	if !config.SkipAuth {
		phaseNum++
		printPhaseHeader(phaseNum, totalPhases, "Authentication Setup")

		result := executeAuthenticationPhase(ctx, config, logFile)
		results = append(results, result)
		printPhaseResult(result)

		if !result.Success {
			fmt.Println("\nAuthentication failed. Stopping execution.")
			os.Exit(1)
		}
	}

	if !config.SkipDocker {
		phaseNum++
		printPhaseHeader(phaseNum, totalPhases, "Docker Daemon Configuration")

		result := executeDockerPhase(ctx, config, logFile)
		results = append(results, result)
		printPhaseResult(result)

		if !result.Success {
			fmt.Println("\nDocker configuration failed. Stopping execution.")
			os.Exit(2)
		}
	}

	if !config.SkipVerify {
		phaseNum++
		printPhaseHeader(phaseNum, totalPhases, "Verification")

		if !config.DryRun {
			verification, err := verifySetup(ctx, config)
			if err != nil {
				fmt.Printf("Verification failed: %v\n", err)
				os.Exit(3)
			}
			printSummary(results, verification)

			if len(verification.Errors) > 0 {
				os.Exit(3)
			}
		} else {
			fmt.Println("  [DRY-RUN] Would verify setup")
			printSummary(results, nil)
		}
	}

	printSuccessBanner(logFile)
}

// =============================================================================
// Phase Execution Functions
// =============================================================================

func executeAuthenticationPhase(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "Authentication", Script: config.AuthScript}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would execute: %s\n", config.AuthScript)
		result.Success = true
		return result
	}

	// Prepare environment variables
	env := []string{
		fmt.Sprintf("GITHUB_USERNAME=%s", config.GitHubUsername),
		fmt.Sprintf("GITHUB_TOKEN=%s", config.GitHubToken),
	}
	if config.DockerUsername != "" {
		env = append(env, fmt.Sprintf("DOCKER_USERNAME=%s", config.DockerUsername))
		env = append(env, fmt.Sprintf("DOCKER_PASSWORD=%s", config.DockerPassword))
	}

	// Execute authentication script
	execResult, err := executeScript(ctx, config.AuthScript, nil, env, config.Verbose, logFile, false)
	if err != nil {
		result.Success = false
		result.Error = err
	} else {
		result.Success = execResult.Success
		result.Duration = execResult.Duration
		result.Output = execResult.Output
	}

	return result
}

func executeDockerPhase(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "Docker Configuration", Script: config.DockerScript}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would execute: %s %s\n", config.DockerScript, strings.Join(config.DockerScriptArgs, " "))
		if config.AutoRestartDocker {
			fmt.Println("  [DRY-RUN] Would restart Docker daemon")
		}
		result.Success = true
		return result
	}

	// Check for sudo privileges if auto-restart is enabled
	if config.AutoRestartDocker && os.Geteuid() != 0 {
		fmt.Println("[FAIL] Auto-restart requires sudo privileges")
		fmt.Println("  Run with: sudo go run main.go")
		result.Success = false
		result.Error = fmt.Errorf("sudo privileges required for auto-restart")
		return result
	}

	// Execute Docker configuration script
	execResult, err := executeScript(ctx, config.DockerScript, config.DockerScriptArgs, nil, config.Verbose, logFile, false)
	if err != nil {
		result.Success = false
		result.Error = err
		if execResult != nil {
			result.Output = execResult.Output
		}
		return result
	}

	result.Success = execResult.Success
	result.Duration = execResult.Duration
	result.Output = execResult.Output

	// Auto-restart Docker daemon
	if result.Success && config.AutoRestartDocker {
		if err := autoRestartDocker(ctx, config.Verbose); err != nil {
			result.Success = false
			result.Error = fmt.Errorf("failed to restart Docker: %w", err)
		}
	}

	return result
}

func executeLogoutPhase(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "Logout", Script: config.LogoutScript}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would execute: %s\n", config.LogoutScript)
		result.Success = true
		return result
	}

	// Build command with flags
	cmdArgs := []string{config.LogoutScript}

	if config.CleanCache {
		cmdArgs = append(cmdArgs, "--clean-cache")
	}

	if config.CleanGhCli {
		cmdArgs = append(cmdArgs, "--clean-gh-cli")
	}

	if config.CleanAll {
		cmdArgs = append(cmdArgs, "--clean-all")
	}

	if config.Force {
		cmdArgs = append(cmdArgs, "--force")
	}

	if config.Verbose {
		cmdArgs = append(cmdArgs, "--verbose")
	}

	// Execute logout script with flags
	cmd := exec.CommandContext(ctx, "bash", cmdArgs...)

	// Setup output
	var stdout, stderr strings.Builder
	if config.Verbose {
		cmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
		cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
	} else {
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr
	}

	// Log output
	if logFile != nil {
		cmd.Stdout = io.MultiWriter(cmd.Stdout, logFile)
	}

	// Execute
	err := cmd.Run()
	duration := time.Since(time.Now())

	result.Success = err == nil
	result.Error = err
	result.Duration = duration
	result.Output = stdout.String() + "\n" + stderr.String()

	return result
}

func executeCacheCleanup(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "Build Cache Cleanup"}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would clean Docker build cache\n")
		result.Success = true
		return result
	}

	// Execute docker buildx prune -a -f
	cmd := exec.CommandContext(ctx, "docker", "buildx", "prune", "-a", "-f")

	var stdout, stderr strings.Builder
	cmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
	cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)

	err := cmd.Run()
	duration := time.Since(time.Now())

	result.Success = err == nil
	result.Error = err
	result.Duration = duration
	result.Output = stdout.String() + "\n" + stderr.String()

	return result
}

func executeGhCliCleanup(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "GitHub CLI Cleanup"}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would clean GitHub CLI data\n")
		result.Success = true
		return result
	}

	// Remove GitHub CLI cache
	cmd := exec.CommandContext(ctx, "rm", "-rf", os.Getenv("HOME")+"/.cache/gh")

	if config.Verbose {
		fmt.Printf("  Removing: %s/.cache/gh\n", os.Getenv("HOME"))
	}

	err := cmd.Run()
	duration := time.Since(time.Now())

	result.Success = err == nil
	result.Error = err
	result.Duration = duration
	result.Output = fmt.Sprintf("Removed %s/.cache/gh", os.Getenv("HOME"))

	return result
}

func executeTempCleanup(ctx context.Context, config *Config, logFile *os.File) *PhaseResult {
	result := &PhaseResult{Name: "Temporary Files Cleanup"}

	if config.DryRun {
		fmt.Printf("  [DRY-RUN] Would clean temporary files\n")
		result.Success = true
		return result
	}

	// Truncate Docker log
	dockerLogCmd := exec.CommandContext(ctx, "sudo", "truncate", "-s", "0", "/var/log/docker.log")
	var stdout, stderr strings.Builder
	dockerLogCmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
	dockerLogCmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
	logErr := dockerLogCmd.Run()

	// Remove BuildKit temp directories
	buildkitCmd := exec.CommandContext(ctx, "rm", "-rf", "/tmp/buildkit-*")
	buildkitCmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
	buildkitCmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
	buildkitErr := buildkitCmd.Run()

	duration := time.Since(time.Now())

	result.Success = logErr == nil && buildkitErr == nil
	if logErr != nil {
		result.Error = logErr
	}
	if buildkitErr != nil {
		if result.Error != nil {
			result.Error = fmt.Errorf("%v (buildkit: %v)", result.Error, buildkitErr)
		} else {
			result.Error = buildkitErr
		}
	}
	result.Duration = duration
	result.Output = stdout.String() + "\n" + stderr.String()

	return result
}

// =============================================================================
// Output and Reporting
// =============================================================================

func printPhaseHeader(phaseNum, total int, name string) {
	fmt.Printf("\n--- Phase [%d/%d]: %s ---\n", phaseNum, total, name)
	fmt.Println(strings.Repeat("-", 50))
}

func printPhaseResult(result *PhaseResult) {
	if result.Success {
		fmt.Printf("[OK] %s completed successfully\n", result.Name)
		if result.Duration > 0 {
			fmt.Printf("  Duration: %s\n", result.Duration)
		}
	} else {
		fmt.Printf("[FAIL] %s failed\n", result.Name)
		if result.Error != nil {
			fmt.Printf("  Error: %v\n", result.Error)
		}
	}
}

func printSuccessBanner(logFile *os.File) {
	fmt.Println()
	fmt.Println("==============================================")
	fmt.Println("           SETUP COMPLETE - SUCCESS")
	fmt.Println("==============================================")
	fmt.Println()

	if logFile != nil {
		logFile.WriteString(fmt.Sprintf("[%s] Setup completed successfully\n",
			time.Now().Format("2006-01-02 15:04:05")))
	}
}

func printLogoutSummary(logFile *os.File) {
	fmt.Println()
	fmt.Println("==============================================")
	fmt.Println("           LOGOUT COMPLETE - SUCCESS")
	fmt.Println("==============================================")
	fmt.Println()
	fmt.Println("Logged out from:")
	fmt.Println("  - Docker Hub (index.docker.io)")
	fmt.Println("  - GHCR (ghcr.io)")
	fmt.Println("  - GCR (gcr.io and regional registries)")
	fmt.Println("  - GitHub CLI (gh)")
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println("  1. Re-authenticate: ./setup-account/loginall.sh")
	fmt.Println("  2. Or run: go run main.go")
	fmt.Println()

	if logFile != nil {
		logFile.WriteString(fmt.Sprintf("[%s] Logout completed successfully\n",
			time.Now().Format("2006-01-02 15:04:05")))
	}
}

// =============================================================================
// Function Implementations
// =============================================================================

func loadConfig() (*Config, error) {
	config := &Config{
		EnvFile: ".env",
		LogDir:  "logs",
	}

	logoutPtr := flag.Bool("logout", false, "Logout from all registries")
	cleanCachePtr := flag.Bool("clean-cache", false, "Clean Docker build cache")
	cleanGhCliPtr := flag.Bool("clean-gh-cli", false, "Clean GitHub CLI data")
	cleanAllPtr := flag.Bool("clean-all", false, "Clean all caches and data")
	forcePtr := flag.Bool("force", false, "Force operation without confirmation")
	skipAuthPtr := flag.Bool("skip-auth", false, "Skip authentication phase")
	skipDockerPtr := flag.Bool("skip-docker", false, "Skip Docker configuration phase")
	skipVerifyPtr := flag.Bool("skip-verify", false, "Skip verification phase")
	verbosePtr := flag.Bool("verbose", false, "Verbose output")
	dryRunPtr := flag.Bool("dry-run", false, "Show commands without executing")
	autoRestartPtr := flag.Bool("auto-restart", false, "Auto-restart Docker daemon")

	flag.Parse()

	config.Logout = *logoutPtr
	config.CleanCache = *cleanCachePtr
	config.CleanGhCli = *cleanGhCliPtr
	config.CleanAll = *cleanAllPtr
	config.Force = *forcePtr
	config.SkipAuth = *skipAuthPtr
	config.SkipDocker = *skipDockerPtr
	config.SkipVerify = *skipVerifyPtr
	config.Verbose = *verbosePtr
	config.DryRun = *dryRunPtr
	config.AutoRestartDocker = *autoRestartPtr

	dir, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	config.WorkDir = dir

	scriptDir := filepath.Join(dir, "script")
	config.ScriptDir = scriptDir
	config.AuthScript = filepath.Join(scriptDir, "loginall.sh")
	config.LogoutScript = filepath.Join(scriptDir, "logoutall.sh")
	config.DockerScript = filepath.Join(scriptDir, "enhancment-docker-builder.sh")
	config.RestoreScript = filepath.Join(scriptDir, "restore-default-config.sh")
	config.DockerScriptArgs = []string{"--yes"}

	if config.Logout {
		config.SkipAuth = true
		config.SkipDocker = true
		config.SkipVerify = true
	}

	if _, err := os.Stat(config.EnvFile); err == nil {
		data, readErr := os.ReadFile(config.EnvFile)
		if readErr == nil {
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if line == "" || strings.HasPrefix(line, "#") {
					continue
				}
				parts := strings.SplitN(line, "=", 2)
				if len(parts) == 2 {
					key := strings.TrimSpace(parts[0])
					value := strings.TrimSpace(parts[1])
					switch key {
					case "GITHUB_USERNAME":
						config.GitHubUsername = value
					case "GITHUB_TOKEN":
						config.GitHubToken = value
					case "DOCKER_USERNAME":
						config.DockerUsername = value
					case "DOCKER_PASSWORD":
						config.DockerPassword = value
					}
				}
			}
		}
	}

	if !config.SkipAuth {
		if config.GitHubUsername == "" {
			return nil, fmt.Errorf("GITHUB_USERNAME not set (required for authentication)")
		}
		if config.GitHubToken == "" {
			return nil, fmt.Errorf("GITHUB_TOKEN not set (required for authentication)")
		}
	}

	return config, nil
}

func setupLogging(logDir string) (*os.File, error) {
	if logDir == "" {
		return nil, nil
	}

	if err := os.MkdirAll(logDir, 0755); err != nil {
		return nil, err
	}

	timestamp := time.Now().Format("2006-01-02_15-04-05")
	logPath := filepath.Join(logDir, fmt.Sprintf("setup_%s.log", timestamp))

	logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return nil, err
	}

	return logFile, nil
}

func executeScript(ctx context.Context, scriptPath string, args []string, env []string, verbose bool, logFile *os.File, _ bool) (*PhaseResult, error) {
	startTime := time.Now()

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("script not found: %s", scriptPath)
	}

	cmdArgs := append([]string{scriptPath}, args...)
	cmd := exec.CommandContext(ctx, "bash", cmdArgs...)

	if len(env) > 0 {
		cmd.Env = append(os.Environ(), env...)
	}

	var stdout, stderr strings.Builder
	multiWriters := []io.Writer{&stdout}

	if verbose {
		multiWriters = append(multiWriters, os.Stdout)
	}
	if logFile != nil {
		multiWriters = append(multiWriters, logFile)
	}

	cmd.Stdout = io.MultiWriter(multiWriters...)
	cmd.Stderr = io.MultiWriter(multiWriters...)

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

func autoRestartDocker(ctx context.Context, verbose bool) error {
	if verbose {
		fmt.Println("Restarting Docker daemon...")
	}

	stopCmd := exec.CommandContext(ctx, "sudo", "systemctl", "stop", "docker.service")
	if verbose {
		stopCmd.Stdout = os.Stdout
		stopCmd.Stderr = os.Stderr
	}
	if err := stopCmd.Run(); err != nil {
		return fmt.Errorf("failed to stop Docker: %w", err)
	}

	time.Sleep(2 * time.Second)

	startCmd := exec.CommandContext(ctx, "sudo", "systemctl", "start", "docker.service")
	if verbose {
		startCmd.Stdout = os.Stdout
		startCmd.Stderr = os.Stderr
	}
	if err := startCmd.Run(); err != nil {
		return fmt.Errorf("failed to start Docker: %w", err)
	}

	maxWait := 30 * time.Second
	checkInterval := 1 * time.Second
	elapsed := time.Duration(0)

	for elapsed < maxWait {
		time.Sleep(checkInterval)
		elapsed += checkInterval

		checkCmd := exec.CommandContext(ctx, "docker", "info")
		if checkCmd.Run() == nil {
			if verbose {
				fmt.Println("Docker daemon is ready")
			}
			return nil
		}
	}

	return fmt.Errorf("Docker daemon did not become ready within %v", maxWait)
}

func verifySetup(ctx context.Context, config *Config) (*VerificationResult, error) {
	result := &VerificationResult{
		Details: []string{},
		Errors:  []string{},
	}

	dockerInfoCmd := exec.CommandContext(ctx, "docker", "info", "--format", "{{json .}}")
	output, err := dockerInfoCmd.CombinedOutput()
	if err != nil {
		result.Errors = append(result.Errors, fmt.Sprintf("Docker daemon not running: %v", err))
	} else {
		result.Details = append(result.Details, "Docker daemon is running")
		result.DockerRunning = true

		if strings.Contains(string(output), "nvidia") {
			result.Details = append(result.Details, "NVIDIA runtime configured")
		}
	}

	dockerConfigPath := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
	data, err := os.ReadFile(dockerConfigPath)
	if err == nil {
		var dockerConfig map[string]interface{}
		if json.Unmarshal(data, &dockerConfig) == nil {
			if auths, ok := dockerConfig["auths"].(map[string]interface{}); ok {
				if _, ok := auths["ghcr.io"]; ok {
					result.Details = append(result.Details, "GHCR authenticated")
					result.GHCRAuthenticated = true
				} else {
					result.Errors = append(result.Errors, "GHCR not authenticated")
				}
			}
		}
	} else {
		result.Errors = append(result.Errors, "Docker config not found")
	}

	daemonPath := "/etc/docker/daemon.json"
	if _, err := os.Stat(daemonPath); err == nil {
		result.Details = append(result.Details, "Docker daemon.json exists")
		result.ConfigApplied = true
	}

	return result, nil
}

func printSummary(results []*PhaseResult, verification *VerificationResult) {
	fmt.Println()
	fmt.Println("==============================================")
	fmt.Println("                    SETUP SUMMARY")
	fmt.Println("==============================================")
	fmt.Println()

	allSuccess := true
	for _, result := range results {
		status := "[OK]"
		if !result.Success {
			status = "[FAIL]"
			allSuccess = false
		}
		fmt.Printf("  %s %s", status, result.Name)
		if result.Duration > 0 {
			fmt.Printf(" (%s)", result.Duration)
		}
		fmt.Println()
	}

	if verification != nil {
		fmt.Println()
		fmt.Println("Verification Results:")
		for _, detail := range verification.Details {
			fmt.Printf("  [OK] %s\n", detail)
		}
		for _, err := range verification.Errors {
			fmt.Printf("  [FAIL] %s\n", err)
		}
	}

	fmt.Println()
	if allSuccess && (verification == nil || len(verification.Errors) == 0) {
		fmt.Println("==============================================")
		fmt.Println("           SETUP COMPLETE - SUCCESS")
		fmt.Println("==============================================")
	} else {
		fmt.Println("==============================================")
		fmt.Println("        SETUP INCOMPLETE - CHECK ERRORS")
		fmt.Println("==============================================")
	}
}

type VerificationResult struct {
	DockerRunning     bool
	GHCRAuthenticated bool
	ConfigApplied     bool
	Details           []string
	Errors            []string
}
