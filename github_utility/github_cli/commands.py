from github import Github
from datetime import datetime, timezone
from dateutil.parser import parse as parse_date
from pprint import pprint
from typing import Optional  # Import Optional for type hinting


def create_issue_from_string(
    github: Github,
    repo: str,
    issue_title: str,
    issue_body: str,
    issue_labels: Optional[list] = None,
    assignees: Optional[list] = None
) -> any:
    """Create an issue with the given title, body, labels, and assignees."""
    if not all([repo, issue_title, issue_body, github]):
        raise ValueError("All parameters must be provided and valid.")

    repository = github.get_repo(repo)

    # Prepare issue data
    issue_data = {
        "title": issue_title,
        "body": issue_body,
    }

    # Add labels if provided
    if issue_labels:
        issue_data["labels"] = [label.strip()
                                for label in issue_labels.split(",")]

    # Add assignees if provided
    if assignees:
        issue_data["assignees"] = [assignee.strip()
                                   for assignee in assignees.split(",")]

    # Create the issue
    issue = repository.create_issue(**issue_data)
    return issue


def post_pr_comment(
    github: Github,
    repo: str,
    pr_number: int,
    comment_body: str,
    comment_id: Optional[int] = None  # Added comment_id parameter
) -> str:
    """Post or update a comment on a pull request using PyGitHub."""
    if not all([repo, pr_number, comment_body, github]):
        raise ValueError("All parameters must be provided and valid.")

    repository = github.get_repo(repo)
    pull_request = repository.get_pull(pr_number)

    if comment_id:
        try:
            # Fetch the existing comment and update it
            comments = repository.get_issues_comments()
            for comment in comments:
                if comment.id == comment_id:
                    comment.edit(comment_body)
                    return f"Comment #{comment_id} updated successfully on PR #{pr_number} in {repo}."
        except Exception as e:
            raise ValueError(f"Failed to update comment #{comment_id}: {e}")
    else:
        # Create a new comment
        pull_request.create_issue_comment(comment_body)
        return f"Comment posted successfully to PR #{pr_number} in {repo}."


def delete_pr_comment(
    github: Github,
    repo: str,
    pr_number: int,
    comment_ids: str
) -> str:
    """Post or update a comment on a pull request using PyGitHub."""
    if not all([repo, pr_number, comment_ids, github]):
        raise ValueError("All parameters must be provided and valid.")

    repository = github.get_repo(repo)
    pull_request = repository.get_pull(pr_number)

    try:
        result = ""
        # Fetch the existing comment and update it
        comments = repository.get_issues_comments()
        for comment in comments:
            for comment_id in comment_ids.split(","):
                if comment.id == int(comment_id):
                    comment.delete()
                    result += f"Comment #{comment_id} deleted successfully on PR #{
                        pr_number} in {repo}.\n"
        return result
    except Exception as e:
        raise ValueError(f"Failed to delete comment #{comment_ids}: {e}")


def is_stale(updated_at: str, days_before_stale: int) -> bool:
    """Check if an item (issue or PR) is stale based on its last update date."""
    last_updated = updated_at.replace(tzinfo=timezone.utc)
    days_since_update = (datetime.now(timezone.utc) - last_updated).days
    return days_since_update >= days_before_stale


def get_stale_label_event(pr, stale_issue_label: str):
    """Get the most recent event applying the stale label."""
    labeled_event = None
    for event in pr.as_issue().get_events():
        if event.event == "labeled" and event.label and event.label.name == stale_issue_label:
            labeled_event = event
    return labeled_event


def get_comments_ids(github: Github, repo: str, pr_number: int, message_substring: str, user_type: str) -> list:
    """
    Fetch all comments in a pull request and extract comment IDs based on a specific condition.
    """
    repository = github.get_repo(repo)
    pull_request = repository.get_pull(pr_number)
    comments = pull_request.get_issue_comments()

    matching_comment_ids = []
    for comment in comments:
        if user_type:
            if comment.user.type == user_type and message_substring in comment.body:
                matching_comment_ids.append(comment.id)
        else:
            if message_substring in comment.body:
                matching_comment_ids.append(comment.id)

    return matching_comment_ids


def process_issues(
    github: Github,
    repo: str,
    stale_issue_label: str,
    days_before_stale: int,
    days_before_close: int
):
    """Process stale issues."""
    repository = github.get_repo(repo)
    issues = repository.get_issues(state="open", labels=[])

    print(f"Processing {issues.totalCount} issues...")

    for issue in issues:
        try:
            # Skip if it's a PR (issues API includes PRs)
            if issue.pull_request:
                continue

            # Check if the issue is stale
            if is_stale(issue.updated_at, days_before_stale):
                if stale_issue_label not in [label.name for label in issue.labels]:
                    print(
                        f"Issue #{issue.number} is stale. Adding stale label.")
                    issue.add_to_labels(stale_issue_label)
                elif is_stale(issue.updated_at, days_before_stale + days_before_close):
                    print(
                        f"Issue #{issue.number} is stale and will be closed.")
                    issue.edit(state="closed")
            else:
                print(f"Issue #{issue.number} is not stale.")
        except Exception as e:
            print(f"Error processing issue #{issue.number}: {e}")
            continue


def process_pull_requests(
    github: Github,
    repo: str,
    stale_pr_message: str,
    stale_issue_label: str,
    exempt_labels: list,
    days_before_stale: int,
    days_before_close: int
):
    """Process stale pull requests."""
    repository = github.get_repo(repo)
    prs = repository.get_pulls(state="open")

    print(f"Processing {prs.totalCount} pull requests...")

    for pr in prs:
        try:
            label_names = [label.name for label in pr.labels]

            # Skip if PR has an exempt label
            if any(label_name in exempt_labels for label_name in label_names):
                if stale_issue_label in label_names:
                    pr.as_issue().remove_from_labels(stale_issue_label)
                print(f"Skipping PR #{pr.number} due to exempt label.")
                continue

            # Check if the PR is stale
            if stale_issue_label in label_names:
                # Marking a PR stale bumps updated_at, so the close countdown
                # is measured from when the stale label was applied instead.
                labeled_event = get_stale_label_event(pr, stale_issue_label)
                if labeled_event is None:
                    # No labeled event found; fall back to the last update.
                    labeled_at = pr.updated_at
                    stale_marking_completed_at = labeled_at
                else:
                    labeled_at = labeled_event.created_at
                    # Older runs posted the stale comment after adding the
                    # label, so treat the matching comment from the same
                    # actor as part of the marking, not as new activity.
                    stale_marking_completed_at = labeled_at
                    for comment in pr.get_issue_comments():
                        if (
                            comment.user.login == labeled_event.actor.login
                            and comment.body == stale_pr_message
                            and comment.created_at >= labeled_at
                        ):
                            stale_marking_completed_at = max(
                                stale_marking_completed_at,
                                comment.created_at,
                            )
                updated_at = pr.updated_at.replace(tzinfo=timezone.utc)
                if updated_at > stale_marking_completed_at.replace(tzinfo=timezone.utc):
                    print(
                        f"PR #{pr.number} was updated after being marked stale. Removing stale label.")
                    pr.as_issue().remove_from_labels(stale_issue_label)
                elif is_stale(labeled_at, days_before_close):
                    print(f"PR #{pr.number} is stale and will be closed.")
                    pr.edit(state="closed")
                else:
                    print(
                        f"PR #{pr.number} is marked stale; the stale label was applied less than {days_before_close} days ago.")
            elif is_stale(pr.updated_at, days_before_stale):
                print(
                    f"PR #{pr.number} is stale. Adding stale label and posting comment.")
                pr.create_issue_comment(stale_pr_message)
                # Add the label last so its timestamp marks when stale marking completed.
                pr.as_issue().add_to_labels(stale_issue_label)
            else:
                print(f"PR #{pr.number} is not stale.")
        except Exception as e:
            print(f"Error processing PR #{pr.number}: {e}")
            continue


def get_pr_base_sha(github: Github, repo: str, pr_number: int) -> str:
    """
    Fetch the base commit SHA of a pull request.
    """
    repository = github.get_repo(repo)
    pull_request = repository.get_pull(pr_number)
    return pull_request.base.sha
