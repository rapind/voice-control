# Issue Tracker: Beans

Tasks, issues, and PRDs for this repository are tracked with the Beans CLI. Issues are called beans and are stored in `.beans/`.

## Conventions

- Run `beans prime` before managing work so you have the current repository instructions.
- Use `--json` when reading or changing beans.
- Before starting work, find an existing bean or create one with an explicit type and `in-progress` status.
- Keep the bean checklist current as work proceeds.
- Before completing a bean, check every item and append a `## Summary of Changes` section.
- Delete completed beans with `beans delete <bean-id> --force`. Do not archive completed porting beans.

## When a skill says "publish to the issue tracker"

Create an appropriately typed bean with `beans create` and include the published content in its body.

## When a skill says "fetch the relevant ticket"

Use `beans show --json <bean-id>`. If no ID is given, use `beans list --json` with an appropriate search or filter first.
