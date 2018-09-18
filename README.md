# GitHub-Jira-Superdesk workflow utilities

### A collection of helpers for more efficient GitHub-JIRA-Superdesk workflow. The code itself is not that nice and works only for `superdesk-client-core`. PRs welcome :)

### Setup:

Installing [Hub](https://hub.github.com/) is **required** for submitting of the pull requests to work.

Don't forget to add the configs specified in `sd-workflow-config.bash` to your `.bashrc` in order for helpers to work.

### Usage:

`@taskStart [jira-task-id]` - Fetches task title from supplied ID, creates a git branch with received name, assings task to you and marks it as in progress on JIRA.

`@taskFinish` - Runs tests, pushes to GitHub and submits a pull request.

`python3 superdesk-automerge.py` - Watches your pull requests on GitHub and merges then they are approved with tests passing and no merge conflicts "WIP" tag or "DEPENDS ON:" comment present. After the PR is merged, the script restarts the instance waits for it to reload and assings the task to QA.

### Other helpers worth mentioning:

`@checkoutpr [pr-id]` - Checks out PR locally.

`@reviewpr [pr-id]` - Checks out PR locally, merges to master and resets the merge, so all changes are visible in your diff tool of choice.

`@review-commit [commit-id]` - The same as `@reviewpr`, but works on a commit instead of a PR.