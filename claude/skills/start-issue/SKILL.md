---
name: start-issue
description: >-
  Kick off implementation of a Linear issue. Reads the issue, discovers
  available skills, recommends which to load based on issue content,
  confirms with the user, then loads them into context.
argument-hint: "<issue-id>"
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Skill, Agent, AskUserQuestion
---

**Argument:** $ARGUMENTS

If `$ARGUMENTS` is `help`, read and output the contents of this
skill's `README.md` instead of executing the skill. Stop after
outputting the README.

# Start Issue

Transition a Linear issue from "read" to "execute" by loading the
right skills before any code is written.

```
/start-issue INT-123     # Read issue, recommend skills, begin work
/start-issue help        # Show README
```

## Workflow

### 1. Read the Linear Issue

Use Linear MCP tools to fetch the issue by identifier (`$ARGUMENTS`).
Collect: title, description, labels, project, milestone, team,
sub-issues, and any linked issues or PRs.

If no Linear MCP tools are available, ask the user for the issue
details (title, description, type of work).

### 2. Discover Available Skills

Scan for skills in two locations:

**Org-wide (botfiles plugin):**

Find all `hb:*` skills by checking the system-reminder for registered
skill names. These are the skills listed after `hb:` in the skills
list.

**Repo-local:**

```bash
find .claude/skills -name "SKILL.md" -maxdepth 3 2>/dev/null
```

For each discovered skill, read the frontmatter `name`,
`description`, and `paths` fields. Build a catalog of available
skills with their descriptions.

### 3. Analyze and Recommend

Match issue content against the skill catalog. Use these signals:

**From the issue:**

- Title and description keywords
- Labels (e.g., `Feature`, `Bug`, `Escalation`)
- Team assignment (maps to domain)
- Project context
- Linked Figma URLs, Notion docs, or other references

**Keyword-to-skill mapping (non-exhaustive — use judgment):**

| Signal                                                     | Recommended Skills                                          |
| ---------------------------------------------------------- | ----------------------------------------------------------- |
| UI, component, design, frontend, React, page, layout, form | `react`, `typescript`, `testing-library`, `nextjs`, `jsdoc` |
| Figma URL or "figma" in description                        | `figma`                                                     |
| Rails, model, controller, migration, service, concern, API | `rails`, `ruby`, `rspec`                                    |
| Test, spec, coverage                                       | `vitest` or `rspec` (based on stack)                        |
| E2E, end-to-end, browser, Playwright                       | `playwright`                                                |
| CI, pipeline, build, deploy                                | `circleci`                                                  |
| Docker, image, container, k8s                              | `docker-base-image`                                         |
| HBN, network, connection, verification, digest             | `hbn`                                                       |
| Infrastructure, Terraform, k8s                             | Check for infra-related skills                              |
| Bug, fix, regression                                       | `clean-code` + stack-specific skills                        |

**Always include:**

- `typescript` — if work touches any `.ts`/`.tsx` files
- `git` — for branch naming and commit conventions
- `clean-code` — for quality standards
- `github` — for PR conventions

**Include repo-local skills** when their `paths` or `description`
match the work. These often contain project-specific generators,
patterns, or conventions that org-wide skills don't cover.

### 4. Present and Confirm

Show the issue summary, plan of attack, and skill recommendations.

**Issue summary:** A 2–3 sentence plain-language explanation of the
problem and why it matters. This orients the reader before diving
into specifics.

**Plan of attack:** A numbered list of concrete steps you'll take to
complete the issue. Derived from the issue description, acceptance
criteria, and your understanding of the codebase. Keep it actionable
— each step should be something you can start and finish.

**Skills:** Grouped into always-loaded, issue-specific, and
not-loading categories.

Format:

```
Issue: INT-123 — Add user preference panel to settings page
Team: Client Experience
Type: Feature
Project: Settings Redesign (Cycle 12)

Summary
=======
Brief plain-language description of what's wrong or what needs to
happen, and why it matters. Ground the reader in the problem before
jumping to implementation.

Plan of Attack
==============
1. Explore the relevant code (specific areas to look at)
2. First concrete change
3. Second concrete change
4. Write/update tests
5. QA and verify acceptance criteria

Recommended Skills
==================

Always loaded:
  - hb:typescript — TypeScript conventions
  - hb:git — Branch naming and commits
  - hb:clean-code — Quality standards
  - hb:github — PR conventions

Issue-specific:
  - hb:react — React component conventions
  - hb:nextjs — App Router patterns
  - hb:testing-library — Component test conventions
  - hb:figma — Figma design extraction
  - hb:jsdoc — Documentation standards

Repo-local:
  - frontend-generator — Component scaffolding for this project

Not loading (available if needed):
  - hb:rails, hb:ruby, hb:rspec — Backend (not relevant here)
  - hb:playwright — E2E tests (add later if needed)
```

Ask the user:

> Does this look right? Adjust the plan or skills, or say "go" to
> proceed.

Wait for confirmation. The user may adjust the plan, add/remove
skills, or refine scope.

### 5. Load Skills

For each confirmed skill, invoke it via the `Skill` tool so its
guidance is loaded into context. Load them in this order:

1. Stack/language conventions (typescript, ruby, etc.)
2. Framework conventions (react, nextjs, rails, etc.)
3. Testing conventions (testing-library, rspec, vitest, etc.)
4. Tool integrations (figma, circleci, etc.)
5. Repo-local skills (project-specific generators, patterns)
6. Workflow skills (git, github, clean-code)

### 6. Brief and Yield

After loading skills, summarize what's been loaded and present a
compact issue brief:

```
Ready
=====
Issue:   INT-123 — Add user preference panel to settings page
Branch:  INT-123/add-user-preference-panel
Skills:  typescript, react, nextjs, testing-library, figma,
         frontend-generator, git, clean-code, github

Acceptance Criteria
-------------------
- [ ] criteria from the issue...
```

Then ask:

> How would you like to proceed? (e.g., `/frontend-generator`,
> start with architecture, explore the codebase first, etc.)

Do NOT begin implementation automatically. The user drives next
steps — this skill's job is to ensure the right context is loaded
before any code is written.

## Edge Cases

**No `$ARGUMENTS` provided:**

Ask the user for a Linear issue identifier.

**Issue not found:**

Report the error and ask the user to verify the identifier.

**Ambiguous work type:**

When the issue could involve multiple stacks (e.g., full-stack
feature), recommend skills for all relevant stacks and let the user
pare down.

**User says "just go":**

If the user wants to skip the confirmation step, proceed with the
recommended skills immediately.
