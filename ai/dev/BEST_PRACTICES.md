# Best Practices for Claude Code Prompts and Slash Commands

## CLAUDE.md Files

### Projct-Based CLAUDE.md

When Claude Code runs in a directory containing a CLAUDE.md file, it will be automatically added to your context. This file serves multiple purposes:

**Note:** Claude Code will suggest adding newly learned information (like code style preferences or important commands) to CLAUDE.md so it remembers for next time.

1. **Store frequently used commands**
   ```markdown
   ## Build Commands
   - Build: `npm run build`
   - Test: `npm test`
   - Lint: `npm run lint`
   - Deploy: `./scripts/deploy.sh production`
   ```

2. **Document code style preferences**
   ```markdown
   ## Code Style
   - Use TypeScript strict mode
   - Prefer functional components with hooks
   - Use camelCase for variables, PascalCase for components
   - Always include JSDoc comments for public functions
   ```

3. **Maintain codebase structure information**
   ```markdown
   ## Project Structure
   - `/src/components` - React components
   - `/src/services` - API and business logic
   - `/src/utils` - Shared utilities
   - Database migrations in `/migrations`
   ```

### Global CLAUDE.md Best Practices

For system-wide preferences that apply across all projects:

```markdown
## General Preferences
- Always ask before making destructive changes
- Prefer explicit error handling over silent failures
- Write comprehensive tests for new features
- Use semantic commit messages

## Security Practices
- Never commit secrets or API keys
- Always validate user input
- Use parameterized queries for database operations
```

## Slash Commands

### Creating Custom Slash Commands

Store prompt templates in Markdown files within the .claude/commands folder. These become available through the slash commands menu when you type /. You can check these commands into git to make them available for the rest of your team.

#### Project-Specific Commands

Location: `.claude/commands/[command-name].md`

**Example: Fix GitHub Issue**
```markdown
Please analyze and fix the GitHub issue: $ARGUMENTS

Steps:
1. Read the issue description
2. Identify the root cause
3. Implement a solution
4. Add appropriate tests
5. Prepare a concise PR description
```

The special keyword $ARGUMENTS allows passing parameters from command invocation.

#### User-Specific Commands

Location: `~/.claude/commands/[command-name].md`

**Example: Security Review**
```markdown
Review this code for security vulnerabilities, focusing on:
- SQL injection risks
- XSS vulnerabilities
- Authentication bypasses
- Insecure data handling
- Missing input validation
```

### Effective Slash Command Patterns

1. **Task-Oriented Commands**
   ```markdown
   # /refactor-auth
   
   <instructions>
   Refactor the authentication system for improved architecture
   </instructions>
   
   <approach>
   Identify all authentication-related files, analyze current implementation, suggest cleaner architecture, implement changes incrementally, and update tests.
   </approach>
   
   <context>
   Target: $ARGUMENTS
   </context>
   ```

2. **Analysis Commands**
   ```markdown
   # /performance-audit
   
   <instructions>
   Analyze API performance focusing on database queries and N+1 problems
   </instructions>
   
   <approach>
   Review all API endpoints, measure response times, identify bottlenecks especially in database queries. Present results in markdown table format with columns: Endpoint | Avg Response Time | Suggestions.
   </approach>
   
   <context>
   Target: $ARGUMENTS
   </context>
   ```

3. **Automation Commands**
   ```markdown
   # /fix-lint-errors
   
   <instructions>
   Fix all lint errors in the project systematically
   </instructions>
   
   <approach>
   Run lint command, write errors to markdown checklist, fix each error systematically, re-run lint to verify fixes, then commit with message "fix: resolve lint errors".
   </approach>
   
   <context>
   Target: $ARGUMENTS
   </context>
   ```

## Prompt Writing Best Practices

### 1. Context Setting

Be specific about desired behavior and frame your instructions with modifiers. Claude has been fine-tuned to pay special attention to XML tags.

**Instead of:** "fix the tests"
**Use:** "fix the failing authentication tests by updating the mock data to match the new API response format"

**With XML tags for better structure (3-section maximum):**
```
<instructions>
Fix the failing authentication tests by updating mock data
</instructions>

<approach>
Tests are failing due to API response format change. Update mock data to match new format, ensure all test assertions pass, then run lint and typecheck.
</approach>

<context>
Target: src/tests/auth/
</context>
```

### 2. Break Down Complex Tasks

```
"migrate the user service to TypeScript:
1) convert all .js files to .ts
2) add proper type annotations
3) fix any type errors
4) update the build configuration
5) verify all tests still pass"
```

### 3. Use Role-Based Prompting

"as a security expert, review our authentication implementation and identify potential vulnerabilities"

### 4. Trigger Deep Analysis with Think

For complex problems, use the think command:

```
claude "think about how to optimize the database queries in our e-commerce checkout process"
```

This triggers extended thinking mode for deeper analysis and multiple approaches.

### 5. Specify Output Format

"analyze our API performance and present the results in a markdown table showing endpoint, average response time, and suggestions for improvement"

### 6. Use Checklists for Large Tasks

For large tasks with multiple steps or requiring exhaustive solutions—like code migrations, fixing numerous lint errors, or running complex build scripts—have Claude use a Markdown file as a checklist and working scratchpad:

```
"Fix all lint errors in the project:
1. Run the lint command and write all errors to lint-errors.md
2. Work through each error systematically, checking it off when fixed
3. Re-run lint after each batch of fixes to verify
4. Update the checklist as you progress"
```

## MCP Integration

Project-scoped servers make it easy to ensure everyone on your team has access to the same MCP tools. Before using project-scoped servers from .mcp.json, Claude Code will prompt you to approve them for security.

**Example .mcp.json:**
```json
{
  "servers": {
    "github": {
      "command": "mcp-server-github",
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "postgres": {
      "command": "mcp-server-postgres",
      "args": ["--connection-string", "${DATABASE_URL}"]
    }
  }
}
```

## Advanced Patterns

### 1. Sandbox Mode for Read-Only Operations

Claude Code can use `sandbox=true` for safe read-only operations:

**Safe for sandbox mode:**
- Information gathering: `ls`, `cat`, `head`, `tail`, `find`
- File inspection: `file`, `stat`, `wc`, `diff`
- Git reads: `git status`, `git log`, `git diff`
- Environment checks: `pwd`, `whoami`, `which`

**Requires sandbox=false:**
- Any write operations
- Network requests
- Commands that might need write access (even `gh` for fetching issues)

### 2. Using Hooks for Automation

Claude Code hooks are user-defined shell commands that execute at various points in Claude Code's lifecycle.

**Example: Auto-format on save**
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "/home/user/scripts/format-code.sh"
      }]
    }]
  }
}
```

Note: Hooks receive JSON data via stdin containing session information and event-specific data. You'll need to parse this in your script to get the file path.

### 2. Context Management

During long sessions, Claude's context window can fill with irrelevant conversation, file contents, and commands. Use the /clear command frequently between tasks to reset the context window.

### 3. Parallel Processing

For repeated workflows—debugging loops, log analysis, etc.—store prompt templates in Markdown files. Then use headless mode:

```bash
# Fix multiple files in parallel
for file in src/**/*.js; do
  claude -p "add JSDoc comments to all functions in $file" &
done
```

**Warning:** Parallel processing can consume tokens rapidly. Monitor your usage carefully as costs can escalate quickly with multiple concurrent instances.

## Common Pitfalls to Avoid

1. **Vague Instructions**
   - ❌ "make it better"
   - ✅ "improve performance by implementing caching for database queries"

2. **Missing Context**
   - ❌ "add the new feature"
   - ✅ "add user profile page that matches our existing UI in src/components/auth/"

3. **Overloading Single Prompts**
   - ❌ One massive prompt with 20 requirements
   - ✅ Break into sequential, focused prompts

4. **Ignoring File Structure**
   - Always reference specific paths and existing patterns
   - Use relative paths from project root

## Quick Reference

### Essential Slash Commands
- `/clear` - Reset context between tasks
- `/hooks` - Configure automation
- `/init` - Analyze project and create CLAUDE.md
- `/mcp` - Manage MCP servers
- `/bug` - Report issues
- `/think` - Trigger extended thinking mode for complex problems

### Useful CLI Flags
- `-p` - Headless mode for automation
- `--output-format json` - Structured output
- `--continue` - Resume previous session
- `--verbose` - Debug mode
- `--mcp-debug` - Debug MCP configuration issues

### Key Prompt Patterns
1. **Specific task + location + constraints**
2. **Role + objective + format**
3. **Multi-step with clear progression**
4. **Examples when behavior needs clarification**
