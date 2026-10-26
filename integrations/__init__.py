"""Third-party knowledge base, git, and project management integrations."""

from .agent_service import AgentService, clean_markdown_documentation
from .bitbucket_service import BitbucketService
from .confluence_service import ConfluenceService
from .git_service import GitService
from .github_service import GitHubService
from .gitlab_service import GitLabService
from .hub_service import HubService
from .linear_service import LinearService
from .notion_service import NotionService
from .obsidian_service import ObsidianService

__all__ = [
    "AgentService",
    "clean_markdown_documentation",
    "BitbucketService",
    "ConfluenceService",
    "GitService",
    "GitHubService",
    "GitLabService",
    "HubService",
    "LinearService",
    "NotionService",
    "ObsidianService",
]
