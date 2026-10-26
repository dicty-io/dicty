import git
import os

class GitService:
    def __init__(self, repo_path: str = "."):
        # Resolve path to ensure we can load the repository
        self.repo_path = os.path.abspath(repo_path)
        try:
            self.repo = git.Repo(self.repo_path)
        except git.exc.InvalidGitRepositoryError:
            self.repo = None

    def get_commit_info(self, commit_hashes: list[str]) -> list[dict]:
        if not self.repo:
            return []
        commits_data = []
        for ch in commit_hashes:
            try:
                commit = self.repo.commit(ch)
                # Diff against the parent (or NULL_TREE if initial commit)
                parent = commit.parents[0] if commit.parents else git.NULL_TREE
                diff_index = parent.diff(commit, create_patch=True)
                
                diffs = []
                for d in diff_index:
                    diffs.append({
                        "a_path": d.a_path,
                        "b_path": d.b_path,
                        "diff": d.diff.decode("utf-8", errors="replace") if d.diff else ""
                    })

                commits_data.append({
                    "hexsha": commit.hexsha,
                    "message": commit.message.strip(),
                    "author": commit.author.name,
                    "date": str(commit.authored_datetime),
                    "diffs": diffs
                })
            except Exception as e:
                commits_data.append({
                    "hexsha": ch,
                    "error": f"Failed to retrieve commit: {str(e)}"
                })
        return commits_data
