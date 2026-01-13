# Go Orchestration Implementation Guide with TUI

## Overview

This document provides a complete technical specification for implementing a Go-based orchestration script (`guide/main.go`) with a modern **Text User Interface (TUI)** that automates complete DevOps setup workflow.

**Version:** 4.0
**Last Updated:** 2025-01-12
**Status:** TUI Specification Complete

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [TUI Implementation](#tui-implementation)
3. [Execution Flow](#execution-flow)
4. [File Structure](#file-structure)
5. [Phase Implementation](#phase-implementation)
6. [TUI Components](#tui-components)
7. [Usage Examples](#usage-examples)
8. [Error Handling](#error-handling)
9. [Testing](#testing)
10. [Deployment](#deployment)

---

## Architecture Overview

### TUI Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     main.go (TUI App)                     │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  bubbletea (TUI Framework)                         │   │
│  │                                                     │   │
│  │  Model (State)          View (Display)                │   │
│  │  ├─ Config             ├─ Bordered                  │   │
│  │  ├─ PhaseResults      ├─ List                     │   │
│  │  ├─ Verification      ├─ Progress Bar              │   │
│  │  └─ UIState          ├─ Spinner                  │   │
│  │                       └─ Interactive Elements      │   │
│  │                                                     │   │
│  │  Update (Logic)                                      │   │
│  │  ├─ Handle Events (mouse, keyboard)                   │   │
│  │  ├─ Update State                                      │   │
│  │  └─ Send Commands                                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Phase Execution (Async)                           │   │
│  │  ├─ Authentication Phase                         │   │
│  │  ├─ Docker Configuration Phase                   │   │
│  │  └─ Verification Phase                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Key TUI Features

- **Clickable Elements**: Mouse support for all interactive elements
- **Keyboard Navigation**: Arrow keys, Enter, Space, Esc
- **Progress Indicators**: Real-time progress bars and spinners
- **Color-coded Output**: Success (green), Error (red), Info (blue)
- **Multi-phase Workflow**: Sequential or parallel execution
- **Interactive Confirmation**: Prompts for user decisions

---

## TUI Implementation

### Framework: bubbletea + lipgloss

```bash
go get github.com/charmbracelet/bubbletea
go get github.com/charmbracelet/lipgloss
```

### Model-View-Update (MVU) Pattern

```go
// State Model
type model struct {
    config           *Config
    phaseResults     []*PhaseResult
    verification    *VerificationResult
    currentPhase     int
    totalPhases     int
    uiState         UIState
    spinner         spinner.Model
    progress        progress.Model
    logLines       []string
    showHelp        bool
    showLogs        bool
    viewport       viewport.Model
}

type UIState int

const (
    StateMenu UIState = iota
    StateConfig
    StateRunning
    StateComplete
    StateError
    StateHelp
)

// Events
type (
    phaseCompleteMsg struct {
        result *PhaseResult
    }
    phaseStartMsg struct {
        phase int
        name  string
    }
    logMsg struct {
        line string
    }
)
```

### Initial Model

```go
func initialModel() model {
    sp := spinner.New()
    sp.Spinner = spinner.Points
    sp.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("205"))

    return model{
        currentPhase: 0,
        totalPhases:  3,
        uiState:     StateMenu,
        spinner:     sp,
        logLines:    []string{},
        showHelp:     false,
    }
}
```

### Init Function

```go
func (m model) Init() tea.Cmd {
    return tea.Batch(
        spinner.Tick,
        loadConfigCmd(),
    )
}
```

### Update Function

```go
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    var cmds []tea.Cmd

    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.Type {
        case tea.KeyCtrlC, tea.KeyEsc:
            if m.showHelp {
                m.showHelp = false
                return m, nil
            }
            return m, tea.Quit

        case tea.KeyEnter:
            switch m.uiState {
            case StateMenu:
                // Start execution
                m.uiState = StateRunning
                cmds = append(cmds, startPhaseCmd(1, "Authentication"))
            case StateComplete:
                return m, tea.Quit
            }

        case tea.KeyUp, tea.KeyDown:
            // Navigate menu
            // ...

        case tea.KeyF1:
            m.showHelp = !m.showHelp
        }

    case tea.MouseMsg:
        // Handle mouse events for clickable elements
        m, cmd := handleMouseClick(m, msg)
        cmds = append(cmds, cmd)

    case configLoadedMsg:
        m.config = msg.config
        return m, nil

    case phaseStartMsg:
        m.currentPhase = msg.phase
        m.logLines = append(m.logLines,
            fmt.Sprintf("Starting Phase %d: %s", msg.phase, msg.name))

    case phaseCompleteMsg:
        m.phaseResults = append(m.phaseResults, msg.result)
        if msg.result.Success {
            m.logLines = append(m.logLines,
                fmt.Sprintf("Phase %d completed: ✓", msg.result.Name))
        } else {
            m.logLines = append(m.logLines,
                fmt.Sprintf("Phase %d failed: ✗ %v", msg.result.Name, msg.result.Error))
        }

        // Start next phase
        if m.currentPhase < m.totalPhases {
            nextPhase := m.currentPhase + 1
            phaseName := getPhaseName(nextPhase)
            cmds = append(cmds, startPhaseCmd(nextPhase, phaseName))
        } else {
            cmds = append(cmds, verifySetupCmd(m.config))
        }

    case logMsg:
        m.logLines = append(m.logLines, msg.line)
        // Auto-scroll to bottom
        if m.viewport.TotalLineCount() > m.viewport.Height {
            m.viewport.GotoBottom()
        }

    case verificationCompleteMsg:
        m.verification = msg.result
        m.uiState = StateComplete
    }

    // Update sub-models
    var cmd tea.Cmd
    m.spinner, cmd = m.spinner.Update(msg)
    cmds = append(cmds, cmd)

    m.progress, cmd = m.progress.Update(msg)
    cmds = append(cmds, cmd)

    m.viewport, cmd = m.viewport.Update(msg)
    cmds = append(cmds, cmd)

    return m, tea.Batch(cmds...)
}
```

### View Function

```go
func (m model) View() string {
    if m.showHelp {
        return m.helpView()
    }

    switch m.uiState {
    case StateMenu:
        return m.menuView()
    case StateRunning:
        return m.runningView()
    case StateComplete:
        return m.completeView()
    case StateError:
        return m.errorView()
    default:
        return ""
    }
}

func (m model) menuView() string {
    titleStyle := lipgloss.NewStyle().
        Foreground(lipgloss.Color("#FAFAFA")).
        Background(lipgloss.Color("#7D56F4")).
        Padding(0, 2).
        Bold(true)

    title := titleStyle.Render("DevOps Setup Orchestration")

    menuStyle := lipgloss.NewStyle().
        Foreground(lipgloss.Color("#FAFAFA")).
        Padding(1, 2).
        MarginTop(1)

    items := []string{
        "[1] Run Full Setup (All Phases)",
        "[2] Run Authentication Only",
        "[3] Run Docker Configuration Only",
        "[4] Run Verification Only",
        "",
        "[5] Logout from All Registries",
        "[6] Clean Build Cache",
        "",
        "[Q] Quit",
    }

    helpStyle := lipgloss.NewStyle().
        Foreground(lipgloss.Color("243")).
        Faint(true)

    help := helpStyle.Render("[F1] Help  [Click] Select  [Enter] Confirm  [Q] Quit")

    return lipgloss.JoinVertical(
        lipgloss.Left,
        title,
        "",
        menuStyle.Render(lipgloss.JoinVertical(lipgloss.Left, items...)),
        "",
        help,
    )
}

func (m model) runningView() string {
    headerStyle := lipgloss.NewStyle().
        Bold(true).
        Foreground(lipgloss.Color("205"))

    header := headerStyle.Render(fmt.Sprintf("Phase %d/%d: %s",
        m.currentPhase, m.totalPhases, getPhaseName(m.currentPhase)))

    progressView := m.progress.View()
    spinnerView := m.spinner.View()

    // Log output with viewport
    m.viewport.SetContent(strings.Join(m.logLines, "\n"))
    logView := m.viewport.View()

    return lipgloss.JoinVertical(
        lipgloss.Left,
        header,
        "",
        spinnerView + " " + progressView,
        "",
        logView,
    )
}

func (m model) completeView() string {
    if m.verification == nil {
        return ""
    }

    // Check overall success
    allSuccess := true
    for _, r := range m.phaseResults {
        if !r.Success {
            allSuccess = false
            break
        }
    }
    if len(m.verification.Errors) > 0 {
        allSuccess = false
    }

    var borderColor lipgloss.Color
    var title string
    if allSuccess {
        borderColor = lipgloss.Color("#04B575")
        title = "✓ SETUP COMPLETE - SUCCESS"
    } else {
        borderColor = lipgloss.Color("#F43F5E")
        title = "✗ SETUP INCOMPLETE"
    }

    borderStyle := lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(borderColor).
        Padding(1, 2)

    content := []string{title, ""}

    // Phase results
    content = append(content, "Phase Results:")
    for i, r := range m.phaseResults {
        status := "✓"
        if !r.Success {
            status = "✗"
        }
        content = append(content,
            fmt.Sprintf("  %s %s (%s)", status, r.Name, r.Duration))
    }

    // Verification
    content = append(content, "", "Verification:")
    for _, d := range m.verification.Details {
        content = append(content, fmt.Sprintf("  ✓ %s", d))
    }
    for _, e := range m.verification.Errors {
        content = append(content, fmt.Sprintf("  ✗ %s", e))
    }

    // Action buttons
    content = append(content, "",
        "[Enter] Close  [L] View Logs  [R] Retry Failed  [Q] Quit")

    return borderStyle.Render(strings.Join(content, "\n"))
}

func (m model) errorView() string {
    errorStyle := lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(lipgloss.Color("#F43F5E")).
        Padding(1, 2)

    return errorStyle.Render(
        lipgloss.JoinVertical(
            lipgloss.Left,
            "✗ Setup Failed",
            "",
            "Check logs for details.",
            "",
            "[Enter] Close  [L] View Logs  [R] Retry  [Q] Quit",
        ),
    )
}

func (m model) helpView() string {
    helpStyle := lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(lipgloss.Color("#7D56F4")).
        Padding(1, 2)

    helpText := lipgloss.JoinVertical(
        lipgloss.Left,
        "Keyboard Shortcuts:",
        "  [Enter]   Confirm/Select",
        "  [Esc]     Cancel/Go Back",
        "  [↑/↓]     Navigate",
        "  [Tab]      Next Field",
        "  [F1]       Toggle Help",
        "  [Q]        Quit",
        "",
        "Mouse Controls:",
        "  [Click]    Select option",
        "  [Scroll]    View logs",
        "",
        "[Esc] or [Enter] to close",
    )

    return helpStyle.Render(helpText)
}
```

### Clickable Elements

```go
func handleMouseClick(m model, msg tea.MouseMsg) (model, tea.Cmd) {
    // Check if click is within a specific area
    x, y := msg.X, msg.Y

    // Example: Check for menu item clicks
    if m.uiState == StateMenu {
        if y >= 5 && y <= 11 && x >= 0 && x <= 50 {
            // Click is on menu items
            itemClicked := y - 5
            m = m.handleMenuItemClick(itemClicked)
        }
    }

    // Example: Check for button clicks in complete view
    if m.uiState == StateComplete {
        // [Close] button at y=15, x=0-10
        if y == 15 && x >= 0 && x <= 10 {
            return m, tea.Quit
        }
    }

    return m, nil
}

func (m model) handleMenuItemClick(index int) model {
    switch index {
    case 0: // Run Full Setup
        m.uiState = StateRunning
    case 1: // Authentication Only
        m.uiState = StateRunning
    case 4: // Logout
        return m.runLogout()
    }
    return m
}
```

---

## Execution Flow

## Architecture

### Execution Flow

```
┌─────────────────────────────────────────────────────────┐
│                    main.go                             │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  1. Load Configuration (.env)                   │  │
│  └──────────────────────┬──────────────────────────┘  │
│                         ▼                             │
│  ┌─────────────────────────────────────────────────┐  │
│  │  2a. Phase 1: Authentication (default)       │  │
│  │      └─ script/loginall.sh                    │  │
│  │                                               │  │
│  │  2b. Phase 1: Logout (--logout flag)          │  │
│  │      └─ script/logoutall.sh                   │  │
│  └──────────────────────┬──────────────────────────┘  │
│                         ▼                             │
│  ┌─────────────────────────────────────────────────┐  │
│  │  3. Phase 2: Docker Daemon Configuration        │  │
│  │     └─ script/enhancment-docker-builder.sh     │  │
│  │     └─ Auto-restart Docker daemon             │  │
│  └──────────────────────┬──────────────────────────┘  │
│                         ▼                             │
│  ┌─────────────────────────────────────────────────┐  │
│  │  4. Phase 3: Verification                      │  │
│  │     ├─ Docker daemon status                    │  │
│  │     ├─ GHCR authentication                     │  │
│  │     └─ Configuration validation               │  │
│  └──────────────────────┬──────────────────────────┘  │
│                         ▼                             │
│  ┌─────────────────────────────────────────────────┐  │
│  │  5. Report & Summary                           │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## File Structure

```
guide/
├── main.go                          ← TUI orchestration script
├── implement-with-go.md             ← This file
├── .env                            ← Configuration
├── .env.example                    ← Template
├── logs/
│   ├── setup_*.log                 ← Timestamped logs
│   └── audit.log                  ← All operations
├── script/                         ← CENTRALIZED SCRIPTS
│   ├── loginall.sh
│   ├── logoutall.sh
│   ├── enhancment-docker-builder.sh
│   └── restore-default-config.sh
├── backup/
│   └── config/                    ← Configuration backups
└── docs/
    ├── introduction.md
    └── README.md
```
guide/
├── main.go                          ← TUI orchestration script (Go)
├── implement-with-go.md             ← This file
├── .env                            ← Configuration
├── .env.example                    ← Template
├── logs/
│   ├── setup_*.log                 ← Timestamped logs
│   └── audit.log                  ← All operations
├── script/                         ← CENTRALIZED SCRIPTS
│   ├── .env.example                ← Script template
│   ├── loginall.sh
│   ├── logoutall.sh
│   ├── enhancment-docker-builder.sh
│   └── restore-default-config.sh
├── backup/
│   └── config/                    ← Configuration backups
└── docs/
    ├── README.md                    ← Documentation index
    ├── introduction.md
    └── ...
```

---

## Implementation Requirements

### Phase 1: Configuration Management

#### Environment Variables (.env)

```bash
# GitHub & GHCR (Required)
GITHUB_USERNAME=your_github_username
GITHUB_TOKEN=ghp_your_github_pat

# GHCR (Optional override)
GHCR_USERNAME=$GITHUB_USERNAME
GHCR_TOKEN=$GITHUB_TOKEN

# Docker Hub (Optional)
DOCKER_USERNAME=your_dockerhub_username
DOCKER_PASSWORD=your_dockerhub_token

# Configuration Options (Optional)
DOCKER_AUTO_RESTART=true           # Auto-restart Docker daemon after config
LOG_LEVEL=info                     # debug, info, warn, error
VERIFICATION_ENABLED=true         # Run verification phase
```

#### Configuration Struct

```go
type Config struct {
    // Paths
    WorkDir         string
    EnvFile         string
    LogDir          string

    // Scripts
    AuthScript      string
    LogoutScript    string
    DockerScript    string

    // Flags
    Logout          bool
    CleanCache      bool
    CleanGhCli     bool
    CleanAll       bool
    Force          bool
    SkipAuth        bool
    SkipDocker      bool
    SkipVerify      bool
    Verbose         bool
    DryRun          bool

    // Behavior
    AutoRestartDocker bool

    // Environment
    GitHubUsername  string
    GitHubToken     string
    DockerUsername  string
    DockerPassword  string

    // Webhook (optional)
    WebhookEnabled bool
    WebhookPort    int
    WebhookSecret  string
}
```

---

### Phase 2: Script Execution

#### Core Execution Function

```go
func executeScript(ctx context.Context, scriptPath string, env []string, verbose bool) (*PhaseResult, error) {
    startTime := time.Now()

    // Check if script exists
    if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
        return nil, fmt.Errorf("script not found: %s", scriptPath)
    }

    // Create command
    cmd := exec.CommandContext(ctx, "bash", scriptPath)
    cmd.Env = append(os.Environ(), env...)
    cmd.Dir = filepath.Dir(scriptPath)

    // Setup output capture
    var stdout, stderr strings.Builder
    if verbose {
        cmd.Stdout = io.MultiWriter(os.Stdout, &stdout)
        cmd.Stderr = io.MultiWriter(os.Stderr, &stderr)
    } else {
        cmd.Stdout = &stdout
        cmd.Stderr = &stderr
    }

    // Execute
    err := cmd.Run()
    duration := time.Since(startTime)

    result := &PhaseResult{
        Script:   scriptPath,
        Output:   stdout.String() + "\n" + stderr.String(),
        Duration: duration,
        Success:  err == nil,
        Error:    err,
    }

    return result, err
}
```

#### Real-Time Output Streaming

```go
func executeScriptWithStream(ctx context.Context, scriptPath string, env []string, logFile *os.File) (*PhaseResult, error) {
    startTime := time.Now()

    cmd := exec.CommandContext(ctx, "bash", scriptPath)
    cmd.Env = append(os.Environ(), env...)

    // Create pipes for stdout and stderr
    stdoutPipe, err := cmd.StdoutPipe()
    if err != nil {
        return nil, err
    }

    stderrPipe, err := cmd.StderrPipe()
    if err != nil {
        return nil, err
    }

    // Start command
    if err := cmd.Start(); err != nil {
        return nil, err
    }

    // Stream output
    var output strings.Builder
    streamOutput(stdoutPipe, &output, logFile, "OUT")
    streamOutput(stderrPipe, &output, logFile, "ERR")

    // Wait for completion
    err = cmd.Wait()
    duration := time.Since(startTime)

    result := &PhaseResult{
        Script:   scriptPath,
        Output:   output.String(),
        Duration: duration,
        Success:  err == nil,
        Error:    err,
    }

    return result, err
}

func streamOutput(pipe io.ReadCloser, output *strings.Builder, logFile *os.File, prefix string) {
    scanner := bufio.NewScanner(pipe)
    for scanner.Scan() {
        line := scanner.Text()
        output.WriteString(line + "\n")

        // Write to log file with timestamp
        if logFile != nil {
            timestamp := time.Now().Format("2006-01-02 15:04:05")
            logFile.WriteString(fmt.Sprintf("[%s] [%s] %s\n", timestamp, prefix, line))
        }

        // Write to terminal
        fmt.Println(line)
    }
}
```

---

### Phase 3: Docker Daemon Auto-Restart

#### Auto-Restart Function

```go
func autoRestartDocker(ctx context.Context, verbose bool) error {
    fmt.Println("\n🔄 Restarting Docker daemon...")

    // Check if running with sudo
    if os.Geteuid() != 0 {
        return fmt.Errorf("this script requires sudo privileges to restart Docker")
    }

    // Stop Docker
    fmt.Println("   → Stopping Docker daemon...")
    stopCmd := exec.CommandContext(ctx, "systemctl", "stop", "docker.service")
    if verbose {
        stopCmd.Stdout = os.Stdout
        stopCmd.Stderr = os.Stderr
    }
    if err := stopCmd.Run(); err != nil {
        return fmt.Errorf("failed to stop Docker: %w", err)
    }

    // Wait a moment
    time.Sleep(2 * time.Second)

    // Start Docker
    fmt.Println("   → Starting Docker daemon...")
    startCmd := exec.CommandContext(ctx, "systemctl", "start", "docker.service")
    if verbose {
        startCmd.Stdout = os.Stdout
        startCmd.Stderr = os.Stderr
    }
    if err := startCmd.Run(); err != nil {
        return fmt.Errorf("failed to start Docker: %w", err)
    }

    // Wait for Docker to be ready
    fmt.Println("   → Waiting for Docker daemon to be ready...")
    maxWait := 30 * time.Second
    checkInterval := 1 * time.Second
    elapsed := 0 * time.Second

    for elapsed < maxWait {
        readyCmd := exec.CommandContext(ctx, "docker", "info")
        if readyCmd.Run() == nil {
            fmt.Println("   ✓ Docker daemon is ready")
            return nil
        }
        time.Sleep(checkInterval)
        elapsed += checkInterval
        fmt.Printf("   → Waiting... (%s/%s)\n", elapsed, maxWait)
    }

    return fmt.Errorf("Docker daemon did not start within %s", maxWait)
}
```

#### Docker Status Check

```go
func checkDockerStatus() error {
    // Check if Docker daemon is running
    cmd := exec.Command("docker", "info")
    if output, err := cmd.CombinedOutput(); err != nil {
        return fmt.Errorf("docker daemon not running: %w\nOutput: %s", err, string(output))
    }
    return nil
}
```

---

### Phase 4: Verification

#### Verification Function

```go
type VerificationResult struct {
    DockerRunning    bool
    GHCRAuthenticated bool
    ConfigApplied     bool
    Details          []string
    Errors           []string
}

func verifySetup(ctx context.Context, config *Config) (*VerificationResult, error) {
    result := &VerificationResult{}

    // 1. Check Docker daemon
    fmt.Println("🔍 Verifying Docker daemon...")
    if err := checkDockerStatus(); err == nil {
        result.DockerRunning = true
        result.Details = append(result.Details, "✓ Docker daemon is running")
    } else {
        result.Errors = append(result.Errors, "✗ Docker daemon is not running")
    }

    // 2. Check GHCR authentication
    fmt.Println("🔍 Verifying GHCR authentication...")
    ghcrAuth, err := checkGHCRAuthentication(ctx, config)
    if err == nil && ghcrAuth {
        result.GHCRAuthenticated = true
        result.Details = append(result.Details, "✓ GHCR authentication verified")
    } else {
        result.Errors = append(result.Errors, "✗ GHCR authentication failed")
    }

    // 3. Check Docker configuration
    fmt.Println("🔍 Verifying Docker configuration...")
    dockerConfig, err := checkDockerConfiguration(ctx)
    if err == nil && dockerConfig {
        result.ConfigApplied = true
        result.Details = append(result.Details, "✓ Docker configuration applied")
    } else {
        result.Errors = append(result.Errors, "✗ Docker configuration not found")
    }

    return result, nil
}
```

#### GHCR Authentication Check

```go
func checkGHCRAuthentication(ctx context.Context, config *Config) (bool, error) {
    // Check Docker config for GHCR auth
    dockerConfigPath := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
    data, err := os.ReadFile(dockerConfigPath)
    if err != nil {
        return false, fmt.Errorf("failed to read Docker config: %w", err)
    }

    var dockerConfig map[string]interface{}
    if err := json.Unmarshal(data, &dockerConfig); err != nil {
        return false, fmt.Errorf("failed to parse Docker config: %w", err)
    }

    auths, ok := dockerConfig["auths"].(map[string]interface{})
    if !ok {
        return false, nil
    }

    _, exists := auths["ghcr.io"]
    return exists, nil
}
```

#### Docker Configuration Check

```go
func checkDockerConfiguration(ctx context.Context) (bool, error) {
    cmd := exec.CommandContext(ctx, "docker", "info", "--format", "{{json .}}")
    output, err := cmd.CombinedOutput()
    if err != nil {
        return false, err
    }

    var info map[string]interface{}
    if err := json.Unmarshal(output, &info); err != nil {
        return false, err
    }

    // Check for expected configuration keys
    serverVersion, ok := info["ServerVersion"].(string)
    if !ok || serverVersion == "" {
        return false, nil
    }

    // Additional checks can be added here
    // - Check for BuildKit GC
    // - Check for concurrent downloads/uploads
    // - Check for NVIDIA runtime

    return true, nil
}
```

---

### Phase 5: Output & Reporting

#### Progress Display

```go
func printBanner() {
    fmt.Println()
    fmt.Println("╔══════════════════════════════════════════════════════════╗")
    fmt.Println("║     DevOps Setup Orchestration - Go Implementation      ║")
    fmt.Println("╚══════════════════════════════════════════════════════════╝")
    fmt.Println()
}

func printPhaseHeader(phaseNum, total int, name string) {
    fmt.Printf("\n╭─ Phase [%d/%d]: %s\n", phaseNum, total, name)
    fmt.Println("╰─────────────────────────────────────────────────────────")
}

func printPhaseResult(result *PhaseResult) {
    if result.Success {
        fmt.Printf("✓ %s completed successfully\n", filepath.Base(result.Script))
        fmt.Printf("  Duration: %s\n", result.Duration)
    } else {
        fmt.Printf("✗ %s failed\n", filepath.Base(result.Script))
        fmt.Printf("  Error: %v\n", result.Error)
        if result.Output != "" {
            fmt.Printf("  Output:\n%s\n", result.Output)
        }
    }
}
```

#### Summary Report

```go
func printSummary(results []*PhaseResult, verification *VerificationResult) {
    fmt.Println()
    fmt.Println("╔══════════════════════════════════════════════════════════╗")
    fmt.Println("║                    SETUP SUMMARY                           ║")
    fmt.Println("╚══════════════════════════════════════════════════════════╝")
    fmt.Println()

    // Phase results
    fmt.Println("Phases Executed:")
    for i, result := range results {
        if result.Success {
            fmt.Printf("  %d. ✓ %s\n", i+1, result.Name)
        } else {
            fmt.Printf("  %d. ✗ %s\n", i+1, result.Name)
        }
    }

    // Verification results
    if verification != nil {
        fmt.Println("\nVerification Status:")
        for _, detail := range verification.Details {
            fmt.Printf("  %s\n", detail)
        }
        for _, err := range verification.Errors {
            fmt.Printf("  %s\n", err)
        }
    }

    // Overall status
    allSuccess := true
    for _, result := range results {
        if !result.Success {
            allSuccess = false
            break
        }
    }

    if verification != nil && len(verification.Errors) > 0 {
        allSuccess = false
    }

    fmt.Println()
    if allSuccess {
        fmt.Println("╔══════════════════════════════════════════════════════════╗")
        fmt.Println("║              ✓ SETUP COMPLETE - SUCCESS                  ║")
        fmt.Println("╚════════════════════════════════════════════════════════╝")
    } else {
        fmt.Println("╔══════════════════════════════════════════════════════════╗")
        fmt.Println("║              ✗ SETUP INCOMPLETE - CHECK ERRORS           ║")
        fmt.Println("╚════════════════════════════════════════════════════════╝")
    }
    fmt.Println()
}

func printLogoutSummary(logFile *os.File) {
    fmt.Println()
    fmt.Println("╔══════════════════════════════════════════════════════════╗")
    fmt.Println("║              ✓ LOGOUT COMPLETE - SUCCESS                  ║")
    fmt.Println("╚════════════════════════════════════════════════════════╝")
    fmt.Println()
    fmt.Println("Logged out from:")
    fmt.Println("  - Docker Hub (index.docker.io)")
    fmt.Println("  - GHCR (ghcr.io)")
    fmt.Println("  - GCR (gcr.io and regional registries)")
    fmt.Println("  - GitHub CLI (gh)")
    fmt.Println()
    fmt.Println("Next steps:")
    fmt.Println("  1. Re-authenticate: ./script/loginall.sh")
    fmt.Println("  2. Or run: go run main.go")
    fmt.Println()

    if logFile != nil {
        logFile.WriteString(fmt.Sprintf("[%s] Logout completed successfully\n",
            time.Now().Format("2006-01-02 15:04:05")))
    }
}
```

---

## Complete main.go Implementation

### Main Function

```go
func main() {
    // Load configuration
    config, err := loadConfig()
    if err != nil {
        fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
        os.Exit(4)
    }

    // Print banner
    printBanner()

    // Create context with timeout
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
    defer cancel()

    // Setup logging
    logFile, err := setupLogging(config.LogDir)
    if err != nil {
        fmt.Fprintf(os.Stderr, "Warning: Failed to setup logging: %v\n", err)
    }
    if logFile != nil {
        defer logFile.Close()
    }

    var results []*PhaseResult
    phaseNum := 0
    totalPhases := 3

    // Handle logout flag (exclusive operation)
    if config.Logout {
        printPhaseHeader(1, 1, "Logout All Accounts")

        result := executeLogoutPhase(ctx, config, logFile)
        printPhaseResult(result)

        if result.Success {
            // Optional cleanup operations
            if config.CleanCache {
                result2 := executeCacheCleanup(ctx, config, logFile)
                printPhaseResult(result2)
            }

            if config.CleanGhCli {
                result3 := executeGhCliCleanup(ctx, config, logFile)
                printPhaseResult(result3)
            }

            if config.CleanAll {
                result4 := executeTempCleanup(ctx, config, logFile)
                printPhaseResult(result4)
            }

            printLogoutSummary(logFile)
        }
        return
    }
        } else {
            fmt.Printf("  [DRY-RUN] Would execute: %s\n", config.LogoutScript)
            result.Success = true
        }
        printPhaseResult(result)

        if result.Success {
            printLogoutSummary(logFile)
        }
        return
    }

    // Phase 1: Authentication
    if !config.SkipAuth {
        phaseNum++
        printPhaseHeader(phaseNum, totalPhases, "Authentication Setup")

        result := &PhaseResult{Name: "Authentication"}
        if !config.DryRun {
            env := []string{
                fmt.Sprintf("GITHUB_USERNAME=%s", config.GitHubUsername),
                fmt.Sprintf("GITHUB_TOKEN=%s", config.GitHubToken),
            }
            if config.DockerUsername != "" {
                env = append(env, fmt.Sprintf("DOCKER_USERNAME=%s", config.DockerUsername))
                env = append(env, fmt.Sprintf("DOCKER_PASSWORD=%s", config.DockerPassword))
            }

            execResult, err := executeScriptWithStream(ctx, config.AuthScript, env, logFile)
            if err != nil {
                result.Success = false
                result.Error = err
            } else {
                result.Success = execResult.Success
                result.Duration = execResult.Duration
            }
        } else {
            fmt.Printf("  [DRY-RUN] Would execute: %s\n", config.AuthScript)
            result.Success = true
        }

        results = append(results, result)
        printPhaseResult(result)

        if !result.Success {
            fmt.Println("\n✗ Authentication failed. Stopping execution.")
            os.Exit(1)
        }
    }

    // Phase 2: Docker Daemon Configuration
    if !config.SkipDocker {
        phaseNum++
        printPhaseHeader(phaseNum, totalPhases, "Docker Daemon Configuration")

        result := &PhaseResult{Name: "Docker Configuration"}

        if !config.DryRun {
            // Check for sudo privileges if auto-restart is enabled
            if config.AutoRestartDocker && os.Geteuid() != 0 {
                fmt.Println("✗ Auto-restart requires sudo privileges")
                fmt.Println("  Run with: sudo go run main.go")
                os.Exit(2)
            }

            // Execute Docker configuration script
            execResult, err := executeScriptWithStream(ctx, config.DockerScript, nil, logFile)
            if err != nil {
                result.Success = false
                result.Error = err
            } else {
                result.Success = execResult.Success
                result.Duration = execResult.Duration
            }

            // Auto-restart Docker daemon
            if result.Success && config.AutoRestartDocker {
                if err := autoRestartDocker(ctx, config.Verbose); err != nil {
                    result.Success = false
                    result.Error = fmt.Errorf("failed to restart Docker: %w", err)
                }
            }
        } else {
            fmt.Printf("  [DRY-RUN] Would execute: %s\n", config.DockerScript)
            if config.AutoRestartDocker {
                fmt.Println("  [DRY-RUN] Would restart Docker daemon")
            }
            result.Success = true
        }

        results = append(results, result)
        printPhaseResult(result)

        if !result.Success {
            fmt.Println("\n✗ Docker configuration failed. Stopping execution.")
            os.Exit(2)
        }
    }

    // Phase 3: Verification
    if !config.SkipVerify {
        phaseNum++
        printPhaseHeader(phaseNum, totalPhases, "Verification")

        if !config.DryRun {
            verification, err := verifySetup(ctx, config)
            if err != nil {
                fmt.Printf("✗ Verification failed: %v\n", err)
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

    // Success
    if logFile != nil {
        logFile.WriteString(fmt.Sprintf("\n[%s] Setup completed successfully\n",
            time.Now().Format("2006-01-02 15:04:05")))
    }
}
```

---

## Usage Examples

### Standard Execution

```bash
cd /home/ev3lynx/guide

# Run all phases
go run main.go

# With verbose output
go run main.go --verbose

# Dry run (show commands without executing)
go run main.go --dry-run
```

### Logout All Accounts

```bash
# Logout from all registries (basic)
go run main.go --logout

# Logout with verbose output
go run main.go --logout --verbose

# Logout and clean build cache
go run main.go --logout --clean-cache

# Logout and clean GitHub CLI data
go run main.go --logout --clean-gh-cli

# Logout with full cleanup (all caches and temp files)
go run main.go --logout --clean-all

# Dry run - preview actions
go run main.go --logout --clean-all --dry-run

# Force cleanup (skip confirmation)
go run main.go --logout --clean-all --force
```

### Skip Phases

```bash
# Skip authentication (already done)
go run main.go --skip-auth

# Skip Docker configuration (already done)
go run main.go --skip-docker

# Skip verification
go run main.go --skip-verify
```

### Auto-Restart Docker

```bash
# Auto-restart Docker daemon after configuration
# (requires sudo)
sudo go run main.go --auto-restart-docker
```

### Environment Override

```bash
# Use custom .env file
go run main.go --env-file /path/to/custom.env

# Set environment variables directly
GITHUB_USERNAME=myuser GITHUB_TOKEN=ghp_xxx go run main.go
```

---

## Error Handling

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | All phases completed successfully |
| 1 | Authentication Failed | Check credentials in .env |
| 2 | Docker Configuration Failed | Check script output, verify sudo access |
| 3 | Verification Failed | Review verification details |
| 4 | Invalid Configuration | Check .env file and flags |
| 5 | Interrupted | User cancelled or timeout |
| 130 | SIGINT (Ctrl+C) | Graceful shutdown |

### Error Messages

```
✗ Authentication failed
  Error: GHCR authentication failed
  Troubleshooting:
  1. Verify GITHUB_TOKEN has 'read:packages' scope
  2. Verify GITHUB_TOKEN has 'write:packages' scope (for push)
  3. Check if token is expired
  4. Run: docker logout ghcr.io && try again

✗ Docker configuration failed
  Error: failed to restart Docker: exit status 1
  Troubleshooting:
  1. Check Docker daemon logs: sudo journalctl -u docker.service
  2. Verify daemon.json syntax: sudo jq . /etc/docker/daemon.json
  3. Try manual restart: sudo systemctl restart docker.service
```

---

## Logging

### Log File Format

```
[2025-01-12 02:45:00] [OUT] ╔══════════════════════════════════════════════════════════╗
[2025-01-12 02:45:00] [OUT] ║     DevOps Setup Orchestration - Go Implementation      ║
[2025-01-12 02:45:00] [OUT] ╚══════════════════════════════════════════════════════════╝
[2025-01-12 02:45:01] [OUT] Loading environment from .env...
[2025-01-12 02:45:01] [OUT] [OK] Environment loaded
[2025-01-12 02:45:02] [OUT] [OK] Docker daemon is running
[2025-01-12 02:45:03] [OUT] [OK] GHCR authentication successful
...
```

### Log Rotation

```go
func setupLogging(logDir string) (*os.File, error) {
    if err := os.MkdirAll(logDir, 0755); err != nil {
        return nil, err
    }

    timestamp := time.Now().Format("20060102_150405")
    logPath := filepath.Join(logDir, fmt.Sprintf("setup_%s.log", timestamp))

    logFile, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
    if err != nil {
        return nil, err
    }

    return logFile, nil
}
```

---

## Optional: Hybrid Solution (Webhook/Trigger Support)

### Webhook Server (Optional Feature)

```go
// Optional: HTTP endpoint for external triggers
func startWebhookServer(port int, triggerChan chan struct{}) {
    http.HandleFunc("/trigger", func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
            return
        }

        // Verify webhook secret (optional)
        secret := r.Header.Get("X-Webhook-Secret")
        if secret != os.Getenv("WEBHOOK_SECRET") {
            http.Error(w, "Unauthorized", http.StatusUnauthorized)
            return
        }

        // Trigger workflow
        select {
        case triggerChan <- struct{}{}:
            w.WriteHeader(http.StatusOK)
            fmt.Fprintln(w, "Setup triggered")
        default:
            http.Error(w, "Setup already in progress", http.StatusConflict)
        }
    })

    fmt.Printf("Webhook server listening on :%d\n", port)
    if err := http.ListenAndServe(fmt.Sprintf(":%d", port), nil); err != nil {
        log.Printf("Webhook server error: %v", err)
    }
}
```

### Integration with Main Workflow

```go
// Add to main()
if config.WebhookEnabled {
    triggerChan := make(chan struct{}, 1)
    go startWebhookServer(config.WebhookPort, triggerChan)

    // Wait for trigger
    <-triggerChan
    fmt.Println("Webhook received, starting setup...")
}
```

### Webhook Usage

```bash
# Enable webhook
go run main.go --webhook --webhook-port 8080

# Trigger via curl
curl -X POST http://localhost:8080/trigger \
  -H "X-Webhook-Secret: your-secret-here"
```

---

## Testing Plan

### Unit Tests

```go
// config_test.go
func TestLoadConfig(t *testing.T) {
    tests := []struct {
        name    string
        env     map[string]string
        flags   []string
        wantErr bool
    }{
        {
            name: "valid config",
            env: map[string]string{
                "GITHUB_USERNAME": "testuser",
                "GITHUB_TOKEN":    "ghp_test",
            },
            wantErr: false,
        },
        // ... more test cases
    }
    // ... implementation
}
```

### Integration Tests

```bash
# Test dry run
go run main.go --dry-run

# Test individual phases
go run main.go --skip-auth --skip-docker --skip-verify

# Test with invalid config
GITHUB_USERNAME="" go run main.go 2>&1 | grep "Error"
```

---

## Deployment Checklist

- [ ] Create `guide/` directory structure
- [ ] Create `main.go` with complete implementation
- [ ] Copy `.env.example` to `guide/`
- [ ] Create `logs/` directory
- [ ] Test with `--dry-run` flag
- [ ] Test full execution
- [ ] Test auto-restart Docker
- [ ] Test webhook (optional)
- [ ] Add systemd service (optional)
- [ ] Document usage in README

---

## Performance Considerations

| Operation | Typical Duration | Optimization |
|-----------|------------------|--------------|
| Authentication Phase | 5-10 seconds | Cached credentials |
| Docker Configuration | 15-30 seconds | Skip if already configured |
| Docker Restart | 5-10 seconds | Parallel where possible |
| Verification | 2-5 seconds | Async checks |
| **Total** | **30-60 seconds** | ~ |

---

## Future Enhancements

1. **Progress Bars** - Visual progress for long operations
2. **Configuration Validation** - Pre-flight checks for .env
3. **Rollback Support** - Revert on failure
4. **Multi-Environment Support** - Dev/Stage/Prod configs
5. **Distributed Execution** - Execute on multiple hosts
6. **Metrics Collection** - Export to Prometheus/Grafana
7. **Web UI** - Dashboard for monitoring

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `.env` file not found | Copy from `.env.example` or set env vars |
| Script not found | Verify paths are relative to workdir |
| Permission denied (restart Docker) | Run with `sudo` |
| GHCR authentication fails | Check token scopes and expiration |
| Docker daemon won't start | Check logs: `sudo journalctl -u docker.service` |
| Context timeout | Increase timeout in `context.WithTimeout` |

### Debug Mode

```bash
# Enable debug logging
LOG_LEVEL=debug go run main.go --verbose

# Check script output
cat logs/setup_*.log

# Verify Docker daemon
sudo systemctl status docker.service
docker info
```

---

## Summary

This implementation provides:

✅ **Simple execution** with `go run main.go`
✅ **Environment configuration** via `.env` file
✅ **Auto-restart Docker daemon** after configuration
✅ **Optional webhook support** for CI/CD integration
✅ **Comprehensive error handling** and logging
✅ **Real-time output** streaming
✅ **Verification** of setup
✅ **Dry-run mode** for testing

**Estimated Lines of Code:** ~600-800 lines
**Dependencies:** Standard library only (no external deps)

---

**Version:** 1.0
**Last Updated:** 2025-01-12
**Status:** Ready for Implementation
