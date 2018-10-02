alias @linked="find ./node_modules -maxdepth 1 -type l -printf '%p\n'"
alias @rebase='git fetch && git fetch upstream && git rebase upstream/master'
alias @getCurrentBranchName='git branch | grep ^* | cut -c 3-'

@jira() {
  # @jira "Title" "optional description" - creates a new ticket
  if [ -z "$1" ]
    then
      echo "Specify task title"
      return
  fi

  curl -X POST --data "{\"fields\": {\"project\":{\"key\": \"SDESK\"},\"summary\": \"$1\",\"description\": \"$2\",\"issuetype\": { \"name\": \"Bug\"},\"customfield_10580\": { \"id\": \"10742\" }}}" -H "Content-Type: application/json" -H "Cookie: crowd.token_key=$config__jira_cookie" https://dev.sourcefabric.org/rest/api/2/issue/
}

@sdRestart() {
  curl\
  -L\
  -H "Cookie: AIOHTTP_SESSION=$config__fireq_cookie"\
  https://test.superdesk.org/sd/heads/master/restart
}

@branchCreate() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  git checkout -b $1
}

@getTaskTitle() {

  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  curl \
  -s \
  -X GET \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/api/2/issue/$1" \
  | python3 -c "\
import sys,json,re;\
j=json.load(sys.stdin);\
sys.stdout.write(re.sub(r'[^a-zA-Z0-9]', '-', j['fields']['summary']).lower().strip('-') + '-(' + j['key'] + ')')"
}

@getTaskReporter() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  curl \
  -s \
  -X GET \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/api/2/issue/$1" \
  | python3 -c "\
import sys,json,re;\
j=json.load(sys.stdin);\
sys.stdout.write(j['fields']['reporter']['name'])"
}

@transformDashDelimitedStringToSentence() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  echo $1 | python3 -c "\
import sys,json,re;\
name = re.sub(r'-', ' ', sys.stdin.read());\
sys.stdout.write(name[0].capitalize() + name[1:])"
}

@getCurrentSprint() {
  # 57 for board "Superdesk Editorial Agile"
  curl \
  -s \
  -X GET \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/agile/1.0/board/57/sprint?state=active"\
| python3 -c "\
import sys,json,re;\
j=json.load(sys.stdin);\
sys.stdout.write(str(j['values'][0]['id']))"
}

@getTaskIdFromString() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi
  echo $1 | grep -E --only-match "\(.+\)" | grep -E --only-match [^\(\)]+ | tr -d '\n'
}

@getTaskIdFromBranchName() {
  git branch | grep ^* | grep -E --only-match "\(.+\)" | grep -E --only-match [^\(\)]+
}

@changeTaskStatus() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi
  if [ -z "$2" ]
    then
      echo "No argument supplied"
      return
  fi

  curl \
  -s \
  -X POST \
  --data "{\"transition\":{\"id\": $2}}" \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/api/2/issue/$1/transitions"
}

@jiraAssignTaskToUser() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  curl \
  -s \
  -X PUT \
  --data "{\"fields\":{\"assignee\":{\"name\":\"$2\"}}}" \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/api/2/issue/$1"
}

@jiraAssignToQa(){
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  reporter="$(@getTaskReporter $1)"
  
  if [ $reporter = 'nareg' ] || [ $reporter = 'migelek' ]
  then echo "assigning to reporter:$reporter"; @jiraAssignTaskToUser $1 $reporter
  elif [ $(( ( RANDOM % 2 ) )) -eq 0 ]
  then  echo "assigning randomly: nareg"; @jiraAssignTaskToUser $1 "nareg"
  else echo "assigning randomly: migelek"; @jiraAssignTaskToUser $1 "migelek"
  fi
}

@jiraPutTaskToSprint() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  curl \
  -s \
  -X POST \
  --data "{\"issues\":[\"$1\"]}" \
  -H "Content-Type: application/json" \
  -H "Cookie: crowd.token_key=$config__jira_cookie" \
  "https://dev.sourcefabric.org/rest/agile/1.0/sprint/$2/issue"
}

@moveTaskToReview() {
  @changeTaskStatus $1 5
}

@taskStart() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi
  
  @validateThatThereAreNoUncommitedChanges \
  && git checkout master \
  && @rebase \
  && @branchCreate "$(@getTaskTitle $1)" \
  && @jiraPutTaskToSprint $1 "$(@getCurrentSprint)" \
  && @jiraAssignTaskToUser $1 "$config__jira_username" \
  && @changeTaskStatus $1 4 # 4 for in progress

}

@validateThatThereAreNoUncommitedChanges() {
  if ! [ -z "$(git status -s)" ]
    then
      echo "There are uncommited changes"
      false
    else
      true
  fi
}

@taskFinish() {
  npm run test \
  && @validateThatThereAreNoUncommitedChanges \
  && git push --set-upstream origin "$(@getCurrentBranchName)" \
  && echo $(@transformDashDelimitedStringToSentence "$(@getCurrentBranchName)")$'\n'$(@getTaskIdFromBranchName) | hub pull-request -F - \
  && @moveTaskToReview "$(@getTaskIdFromBranchName)" \
  && git checkout master
}

@checkoutpr() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  git fetch upstream pull/$1/head:"pr-$1"
}

@reviewpr() {
  if [ -z "$1" ]
    then
      echo "No argument supplied"
      return
  fi

  @checkoutpr $1 && @rebase && git merge --squash "pr-$1" && git commit --no-edit && git reset HEAD~1
}

@review-commit() {
  if [ -z "$1" ]
    then
      echo "No argument supplied. First arg for PR id"
      return
  fi

  if [ -z "$1" ]
    then
      echo "No argument supplied. Second arg for commit hash"
      return
  fi

  @checkoutpr $1 && git checkout "pr-$1" && git reset --hard "$2" && git reset HEAD~1
}
