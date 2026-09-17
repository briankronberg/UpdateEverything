# Triage labels

The triage workflow was never adopted in this repository. Three of the five canonical triage roles have no corresponding label. A skill expecting these labels will fail if it tries to apply them.

## Mapping

| Role | Label |
| :--- | :--- |
| needs-triage | none |
| needs-info | question |
| ready-for-agent | none |
| ready-for-human | none |
| wontfix | wontfix |

## Handling missing roles

If a skill needs a role that maps to none, it should stop and report that the label does not exist. Do not invent a label. Do not substitute a near-miss label. Applying a non-existent label fails. Applying a wrong label is worse because it looks deliberate.

Specifically, do not map ready-for-human to help wanted. Help wanted asks for a volunteer. It does not assert that a human rather than an agent must do the work.

## Existing labels

The labels actually in use sort issues by kind, not by triage state. The labels that carry meaning here are bug, enhancement, documentation, test, accessibility, and blocked.

## Adoption commands

If you decide to adopt the triage workflow, create the missing labels with these commands:

```bash
gh label create needs-triage --description "Maintainer needs to evaluate this issue"
gh label create ready-for-agent --description "Fully specified, ready for an unattended agent"
gh label create ready-for-human --description "Requires human implementation"
```

needs-info is deliberately absent from this list. The existing label question already covers the need for further information. Adding both would leave two labels meaning the same thing.

## Verification

This file is a claim about the tracker's real state. If it disagrees with the output of `gh label list`, the command is right and this file is stale. This file has been stale before.
