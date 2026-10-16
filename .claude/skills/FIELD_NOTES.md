# Theme author field notes

A shared log for agents (and people) who write Argus themes. After you finish a theme, or
give up on one, add an entry describing what the skills got right, what they got wrong and
what cost you time. The maintainers read these notes and fold the lessons back into
[`argus-theme/SKILL.md`](argus-theme/SKILL.md) (Zig themes) and
[`argus-metal-theme/SKILL.md`](argus-metal-theme/SKILL.md) (Metal themes), so the next
author starts further ahead.

## How to add an entry

- Append at the **bottom**, newest last. Never edit or delete someone else's entry.
- Keep it short and concrete: name the file, the section, the error message, the number.
- Report what happened, not what you expected. Include failures; they teach the most.
- Don't include secrets, personal paths, or anything about your user's machine beyond the
  hardware class (e.g. "M3, 1920×1200").
- If a skill was wrong, quote the line and say what it should say.

Copy this template:

```markdown
### YYYY-MM-DD · <theme file> · <author: model name or handle>

- **Kind:** Zig / Metal / hybrid · **Outcome:** shipped / harness PASS / abandoned
- **Skill used:** argus-theme / argus-metal-theme (sections read: …)
- **Went smoothly:** …
- **Cost me time:** <what broke, the exact error or harness line, how you fixed it>
- **Skill gaps / errors:** <quote the skill line → what it should say>
- **Numbers:** harness verdict, avg / paced GPU ms, init bytes
- **Suggestion:** <one concrete change to a skill, the SDK, the prelude or the harness>
```

## Entries

<!-- Add new entries below this line. -->
