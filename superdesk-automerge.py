import time
import json
import subprocess
import requests
import re

print("Superdesk automerge started")

github_username = subprocess.check_output("bash -ic 'echo \"$config__github_username\"'", shell=True).decode("utf-8").strip()
github_auth_token = subprocess.check_output("bash -ic 'echo \"$config__github_auth_token\"'", shell=True).decode("utf-8").strip()
github_web_auth_cookie = subprocess.check_output("bash -ic 'echo \"$config__github_web_auth_cookie\"'", shell=True).decode("utf-8").strip()

def merge_pull_request(head_sha, pull_id, pr_author_username, pr_branch_name):

    jira_task_id = subprocess.check_output(f"bash -ic '@getTaskIdFromString \"{pr_branch_name}\"'", shell=True).decode("utf-8")

    request_payload = {
        "commit_title": f"Merge pull request #{pull_id} from {pr_author_username}/{pr_branch_name}",
        "commit_message": jira_task_id,
        "sha": head_sha,
        "merge_method": "squash"
    }

    response = requests.put(
        f"https://api.github.com/repos/superdesk/superdesk-client-core/pulls/{pull_id}/merge",
        data=json.dumps(request_payload),
        auth=(github_username, github_auth_token)
    )

    print(response.text)
    print(subprocess.check_output(f"bash -ic '@sdRestart'", shell=True).decode("utf-8"))
    time.sleep(60 * 10) # 10 minutes for the instance to reload changes
    print(subprocess.check_output(f"bash -ic '@jiraAssignToQa \"{jira_task_id}\"'", shell=True).decode("utf-8"))
    print("\n\n")

def check_pull_requests():
    all_pull_requests = json.loads(
        requests.get(
            'https://api.github.com/repos/superdesk/superdesk-client-core/pulls',
            auth=(github_username, github_auth_token)
        ).text
    )
    
    for pr in all_pull_requests:
        user = pr["user"]["login"]

        if(user == github_username):

            prNumber = pr["number"]

            pr_page_on_github = requests.get(
                f"https://github.com/superdesk/superdesk-client-core/pull/{prNumber}",
                cookies={"user_session": github_web_auth_cookie}
            ).text

            tests_passed_and_pr_approved_and_no_merge_conflicts = "branch-action-state-clean" in pr_page_on_github
            depends_on_other_prs = 'DEPENDS ON:' in pr_page_on_github
            work_in_progress = re.search('sidebar-labels-style .+/labels/wip', pr_page_on_github) is not None

            canMerge = tests_passed_and_pr_approved_and_no_merge_conflicts and not depends_on_other_prs and not work_in_progress

            if(canMerge):
                merge_pull_request(
                    pr["head"]["sha"],
                    pr["number"],
                    user,
                    pr["head"]["ref"]
                )

while True:
    check_pull_requests()
    time.sleep(60 * 5) # 5 minutes