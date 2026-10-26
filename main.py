import os
import dicty_paths  # noqa: F401 - configures sys.path for services and integrations
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
from git_service import GitService
from llm_service import LLMService
from hub_service import HubService
from github_service import GitHubService
from notion_service import NotionService
from confluence_service import ConfluenceService
from obsidian_service import ObsidianService
from pending_manager import PendingManager
from agent_service import AgentService, clean_markdown_documentation
from linear_service import LinearService

load_dotenv()

import httpx
import engine_auth

async def report_status(msg: str):
    for host in ["127.0.0.1:8075", "host.docker.internal:8075"]:
        try:
            req_headers = dict(engine_auth.auth_headers())
            if "host.docker.internal" in host:
                req_headers["Host"] = "127.0.0.1:8075"
            async with httpx.AsyncClient() as client:
                await client.post(f"http://{host}/recording/status/update", json={"status": msg}, headers=req_headers, timeout=0.5)
                break
        except Exception:
            pass

app = FastAPI(title="Voice-to-Knowledge Engine (VKE)")
llm_service = LLMService()
notion_service = NotionService()
pending_manager = PendingManager()

class ReconcileRequest(BaseModel):
    voice_text: str
    commits: list[str]
    target_file: str
    prs: list[int] = None
    issues: list[int] = None
    git_provider: str = "github"
    github_token: str = None
    github_repo: str = None
    gitlab_host: str = "https://gitlab.com"
    gitlab_token: str = None
    gitlab_repo: str = None
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "qwen/qwen3.7-plus"
    llm_api_key: str = ""

@app.get("/")
def read_root():
    return {
        "status": "online",
        "engine": "VKE",
        "llm_model": os.getenv("LLM_MODEL", "not_set")
    }

class PromptUpdateRequest(BaseModel):
    key: str
    value: str

@app.get("/prompts")
def get_prompts():
    from prompts import (
        get_reconcile_system_prompt_default, get_reconcile_system_prompt,
        get_confluence_agent_system_prompt_default, get_confluence_agent_system_prompt,
        get_obsidian_agent_system_prompt_default, get_obsidian_agent_system_prompt,
        get_hub_system_prompt_default, get_hub_system_prompt,
        get_architecture_system_prompt_default, get_architecture_system_prompt,
        get_dictation_custom_system_prompt_default, get_dictation_custom_system_prompt,
        get_dictation_message_system_prompt_default, get_dictation_message_system_prompt,
        get_dictation_email_system_prompt_default, get_dictation_email_system_prompt,
        get_dictation_note_system_prompt_default, get_dictation_note_system_prompt,
        get_dictation_meeting_system_prompt_default, get_dictation_meeting_system_prompt,
        PROMPTS_FILE
    )
    import os
    
    def get_info(key, default_fn, active_fn, description):
        default_val = default_fn()
        active_val = active_fn()
        return {
            "key": key,
            "description": description,
            "default_value": default_val,
            "active_value": active_val,
            "is_custom": active_val != default_val
        }
        
    return [
        get_info("reconcile_system", get_reconcile_system_prompt_default, get_reconcile_system_prompt, "Used for the legacy direct-LLM update system (non-agent mode)."),
        get_info("confluence_agent_system", get_confluence_agent_system_prompt_default, get_confluence_agent_system_prompt, "Controls how the Librarian agent updates Confluence pages, instructing it to read the current page first."),
        get_info("obsidian_agent_system", get_obsidian_agent_system_prompt_default, get_obsidian_agent_system_prompt, "Controls how the Librarian agent updates Obsidian markdown files, including how it discovers and reads existing notes."),
        get_info("hub_system", get_hub_system_prompt_default, get_hub_system_prompt, "Instructions for auto-updating the main index Hub (like README.md) with links to new documentation pages."),
        get_info("architecture_system", get_architecture_system_prompt_default, get_architecture_system_prompt, "Used when the Librarian explores your GitHub repository to build a comprehensive ARCHITECTURE.md file."),
        get_info("dictation_custom_system", get_dictation_custom_system_prompt_default, get_dictation_custom_system_prompt, "The base style instructions used when you select the 'Custom' dictation formatting mode."),
        get_info("dictation_message_system", get_dictation_message_system_prompt_default, get_dictation_message_system_prompt, "Formats voice dictation into a natural, conversational chat message for Slack, iMessage, etc."),
        get_info("dictation_email_system", get_dictation_email_system_prompt_default, get_dictation_email_system_prompt, "Structures voice dictation into a professional, correctly formatted email with greetings and sign-offs."),
        get_info("dictation_note_system", get_dictation_note_system_prompt_default, get_dictation_note_system_prompt, "Organizes your voice dictation into clean, structured markdown notes with headers and bullet points."),
        get_info("dictation_meeting_system", get_dictation_meeting_system_prompt_default, get_dictation_meeting_system_prompt, "Used in Meeting mode to synthesize raw transcripts into actionable summaries and key decisions.")
    ]

import threading
prompts_lock = threading.Lock()

@app.put("/prompts")
def update_prompt(req: PromptUpdateRequest):
    import json
    import os
    from prompts import PROMPTS_FILE
    with prompts_lock:
        data = {}
        if os.path.exists(PROMPTS_FILE):
            try:
                with open(PROMPTS_FILE, "r") as f:
                    data = json.load(f)
            except Exception:
                pass
        data[req.key] = req.value
        with open(PROMPTS_FILE, "w") as f:
            json.dump(data, f, indent=4)
    return {"status": "success"}

@app.delete("/prompts/{key}")
def delete_prompt(key: str):
    import json
    import os
    from prompts import PROMPTS_FILE
    with prompts_lock:
        if os.path.exists(PROMPTS_FILE):
            try:
                with open(PROMPTS_FILE, "r") as f:
                    data = json.load(f)
                if key in data:
                    del data[key]
                    with open(PROMPTS_FILE, "w") as f:
                        json.dump(data, f, indent=4)
            except Exception:
                pass
    return {"status": "success"}

@app.get("/linear/workspaces")
def get_linear_workspaces(linear_api_token: str = "", x_linear_token: str = Header(default="")):
    # Prefer the header so the token never appears in URLs or logs. The query
    # parameter remains for older clients.
    token = x_linear_token.strip() or linear_api_token.strip()
    if not token:
        raise HTTPException(status_code=400, detail="linear_api_token is required")
    try:
        lin = LinearService(token)
        return {"status": "success", "workspaces": lin.list_workspaces()}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/reconcile")
async def reconcile_docs(req: ReconcileRequest):
    # Initialize GitService with provided credentials
    if req.git_provider.lower() == "gitlab":
        from gitlab_service import GitLabService
        dynamic_git = GitLabService(host=req.gitlab_host, token=req.gitlab_token, repo=req.gitlab_repo)
    else:
        dynamic_git = GitHubService(token=req.github_token, repo=req.github_repo)
    
    # 1. Fetch remote git commit metadata & diffs (if provided)
    commits_info = await dynamic_git.get_commit_info(req.commits) if req.commits else []

    # Format git info for prompt
    git_formatted = ""
    for c in commits_info:
        if "error" in c:
            git_formatted += f"Commit: {c['hexsha']}\nError: {c['error']}\n\n"
            continue
        git_formatted += f"Commit: {c['hexsha']}\nAuthor: {c['author']}\nMessage: {c['message']}\n"
        for diff in c.get("diffs", []):
            diff_text = diff['diff']
            if len(diff_text) > 10000:
                diff_text = diff_text[:10000] + "\n...[DIFF TRUNCATED DUE TO LENGTH]..."
            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\nDiff:\n{diff_text}\n"
        git_formatted += "\n"

    # 1B. Fetch Pull Request and Issue details if provided
    github_formatted = ""
    if req.prs:
        for pr_num in req.prs:
            pr_data = await dynamic_git.get_pr_details(pr_num)
            if "error" in pr_data:
                github_formatted += f"PR/MR #{pr_num} Error: {pr_data['error']}\n"
            else:
                github_formatted += f"PR/MR #{pr_data['number']}: {pr_data['title']}\nStatus: {pr_data['state']}\nURL: {pr_data['html_url']}\nDescription: {pr_data['description']}\n\n"
    
    if req.issues:
        for issue_num in req.issues:
            issue_data = await dynamic_git.get_issue_details(issue_num)
            if "error" in issue_data:
                github_formatted += f"Issue #{issue_num} Error: {issue_data['error']}\n"
            else:
                github_formatted += f"Issue #{issue_num}: {issue_data['title']} (State: {issue_data['state']})\nLabels: {', '.join(issue_data.get('labels', []))}\nBody: {issue_data.get('body', '')}\nURL: {issue_data.get('html_url', '')}\n"

    # 2. Read existing target file if it exists
    current_content = ""
    if os.path.exists(req.target_file):
        try:
            with open(req.target_file, "r") as f:
                current_content = f.read()
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to read target file: {str(e)}")

    from prompts import get_reconcile_system_prompt, get_reconcile_user_prompt
    
    # 3. Construct LLM Prompts
    system_prompt = get_reconcile_system_prompt()
    user_prompt = get_reconcile_user_prompt(
        voice_text=req.voice_text,
        git_formatted=git_formatted,
        github_formatted=github_formatted,
        target_file=req.target_file,
        current_content=current_content
    )

    # 4. Generate with LLM
    try:
        updated_content = await llm_service.generate(
            prompt=user_prompt, 
            system_prompt=system_prompt,
            model=req.llm_model,
            api_key=req.llm_api_key,
            provider=req.llm_provider,
            base_url=req.llm_base_url
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"LLM generation failed: {str(e)}")

    # 5. Create Pending Update Proposal
    title = os.path.basename(req.target_file)
    pending_id = pending_manager.create_pending_update(
        title=title,
        original_content=current_content if current_content else "New File: This file does not exist yet.",
        proposed_content=updated_content,
        page_id=req.target_file,
        version=1,
        confluence_url=req.target_file,
        space_key="",
        target_type="local"
    )

    return {
        "status": "success",
        "pending_id": pending_id,
        "file_updated": req.target_file,
        "message": f"Documentation proposal created for {req.target_file}. Review and approve in Pending Updates."
    }

class ConfluenceReconcileRequest(BaseModel):
    voice_text: str
    commits: list[str]
    confluence_url: str
    space_key: str
    username: str
    api_token: str
    page_title: str
    git_provider: str = "github"
    github_token: str = None
    github_repo: str = None
    gitlab_host: str = "https://gitlab.com"
    gitlab_token: str = None
    gitlab_repo: str = None
    prs: list[int] = None
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "openai/gpt-4o-mini"
    llm_api_key: str = ""

@app.post("/reconcile/confluence")
async def reconcile_confluence(req: ConfluenceReconcileRequest):
    await report_status("Fetching remote codebase...")
    if req.git_provider.lower() == "gitlab":
        from gitlab_service import GitLabService
        dynamic_git = GitLabService(host=req.gitlab_host, token=req.gitlab_token, repo=req.gitlab_repo)
    else:
        dynamic_git = GitHubService(token=req.github_token, repo=req.github_repo)
        
    commits_info = await dynamic_git.get_commit_info(req.commits) if req.commits else []

    git_formatted = ""
    for c in commits_info:
        if "error" in c: continue
        git_formatted += f"Commit: {c['hexsha']}\nAuthor: {c['author']}\nMessage: {c['message']}\n"
        for diff in c.get("diffs", []):
            diff_text = diff['diff']
            if len(diff_text) > 10000:
                diff_text = diff_text[:10000] + "\n...[DIFF TRUNCATED DUE TO LENGTH]..."
            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\nDiff:\n{diff_text}\n"

    github_formatted = ""
    if req.prs:
        for pr_num in req.prs:
            pr_data = await dynamic_git.get_pr_details(pr_num)
            if "error" not in pr_data:
                github_formatted += f"PR/MR #{pr_data['number']}: {pr_data['title']}\nDescription: {pr_data['description']}\n"

    conf_service = ConfluenceService(req.confluence_url, req.space_key, req.username, req.api_token)
    page_data = await conf_service.get_page_content_by_title(req.page_title)
    
    current_content = ""
    page_id = req.page_title
    version = 1
    if page_data:
        current_content = page_data["content"]
        version = page_data["version"]

    from prompts import get_confluence_agent_system_prompt, get_confluence_agent_user_prompt
    
    system_prompt = get_confluence_agent_system_prompt()
    user_prompt = get_confluence_agent_user_prompt(
        voice_text=req.voice_text,
        git_formatted=git_formatted,
        github_formatted=github_formatted,
        page_title=req.page_title
    )
    
    agent = AgentService(req.llm_provider, req.llm_base_url, req.llm_model, req.llm_api_key)
    
    def tool_read_document():
        return current_content
        
    async def tool_list_repo_files():
        return await dynamic_git.get_repo_tree()
        
    async def tool_read_repo_file(file_path: str):
        return await dynamic_git.get_file_content(file_path)
        
    tools_funcs = {
        "list_repo_files": (
            {
                "name": "list_repo_files",
                "description": "List all files and directories in the target GitHub repository.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_repo_files
        ),
        "read_repo_file": (
            {
                "name": "read_repo_file",
                "description": "Read the raw content of a specific file in the repository.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_repo_file
        ),
        "read_document": (
            {
                "name": "read_document",
                "description": f"Read the current content of the Confluence page '{req.page_title}'.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_read_document
        ),
        "propose_update": (
            {
                "name": "propose_update",
                "description": "Submit the final updated markdown documentation. You can submit multiple updates at once if multiple files or pages were modified.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "updates": {
                            "type": "array",
                            "description": "List of updates to propose.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "target_file": {
                                        "type": "string",
                                        "description": "The title or identifier of the page being updated."
                                    },
                                    "proposed_content": {
                                        "type": "string",
                                        "description": "The complete, updated markdown content."
                                    }
                                },
                                "required": ["target_file", "proposed_content"]
                            }
                        }
                    },
                    "required": ["updates"]
                }
            },
            None # Handled natively by run_agent_loop
        )
    }

    try:
        await report_status("Agent drafting documentation...")
        final_args = await agent.run_agent_loop(system_prompt, user_prompt, tools_funcs)
        updates = final_args.get("updates", [])
        
        # Fallback for single update if agent didn't follow the array schema properly
        if not updates and "proposed_content" in final_args:
            updates = [{"target_file": req.page_title, "proposed_content": final_args["proposed_content"]}]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    pending_ids = []
    for update in updates:
        target_page = update.get("target_file", req.page_title)
        updated_content = update.get("proposed_content", "")
        
        # If the target page matches the initial request, use the initial content and version, else assume new/empty
        if target_page == req.page_title:
            content_to_use = current_content
            version_to_use = version
        else:
            page_data = await conf_service.get_page_content_by_title(target_page)
            content_to_use = page_data["content"] if page_data else ""
            version_to_use = page_data["version"] if page_data else 1
            
        pending_id = pending_manager.create_pending_update(
            title=target_page,
            original_content=content_to_use,
            proposed_content=updated_content,
            page_id=target_page,
            version=version_to_use,
            confluence_url=req.confluence_url,
            space_key=req.space_key,
            target_type="confluence"
        )
        pending_ids.append(pending_id)
        
    return {"status": "success", "pending_ids": pending_ids}

class ObsidianReconcileRequest(BaseModel):
    voice_text: str
    commits: list[str]
    obsidian_path: str
    page_title: str
    git_provider: str = "github"
    github_token: str = None
    github_repo: str = None
    gitlab_host: str = "https://gitlab.com"
    gitlab_token: str = None
    gitlab_repo: str = None
    prs: list[int] = None
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "openai/gpt-4o-mini"
    llm_api_key: str = ""

@app.post("/reconcile/obsidian")
async def reconcile_obsidian(req: ObsidianReconcileRequest):
    await report_status("Fetching remote codebase...")
    if req.git_provider.lower() == "gitlab":
        from gitlab_service import GitLabService
        dynamic_git = GitLabService(host=req.gitlab_host, token=req.gitlab_token, repo=req.gitlab_repo)
    else:
        dynamic_git = GitHubService(token=req.github_token, repo=req.github_repo)
        
    commits_info = await dynamic_git.get_commit_info(req.commits) if req.commits else []

    git_formatted = ""
    for c in commits_info:
        if "error" in c: continue
        git_formatted += f"Commit: {c['hexsha']}\nAuthor: {c['author']}\nMessage: {c['message']}\n"
        for diff in c.get("diffs", []):
            diff_text = diff['diff']
            if len(diff_text) > 10000:
                diff_text = diff_text[:10000] + "\n...[DIFF TRUNCATED DUE TO LENGTH]..."
            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\nDiff:\n{diff_text}\n"

    github_formatted = ""
    if req.prs:
        for pr_num in req.prs:
            pr_data = await dynamic_git.get_pr_details(pr_num)
            if "error" not in pr_data:
                github_formatted += f"PR/MR #{pr_data['number']}: {pr_data['title']}\nDescription: {pr_data['description']}\n"

    import os
    clean_obsidian_path = req.obsidian_path.strip()
    ob_service = ObsidianService(clean_obsidian_path)
    
    from prompts import get_obsidian_agent_system_prompt, get_obsidian_agent_user_prompt
    
    system_prompt = get_obsidian_agent_system_prompt()
    user_prompt = get_obsidian_agent_user_prompt(
        voice_text=req.voice_text,
        git_formatted=git_formatted,
        github_formatted=github_formatted,
        target_path=clean_obsidian_path,
        page_title=req.page_title
    )
        
    agent = AgentService(req.llm_provider, req.llm_base_url, req.llm_model, req.llm_api_key)
    
    def tool_list_documents():
        md_files = []
        for root, dirs, files in os.walk(clean_obsidian_path):
            if '.git' in dirs:
                dirs.remove('.git')
            for f in files:
                if f.endswith('.md'):
                    rel_path = os.path.relpath(os.path.join(root, f), clean_obsidian_path)
                    md_files.append(rel_path)
        return "\n".join(md_files)
        
    def tool_read_document(file_path: str):
        page_data = ob_service.get_page_content_by_title(file_path)
        if page_data:
            return page_data["content"]
        return "File not found or empty."
        
    async def tool_list_repo_files():
        return await dynamic_git.get_repo_tree()
        
    async def tool_read_repo_file(file_path: str):
        return await dynamic_git.get_file_content(file_path)
        
    tools_funcs = {
        "list_repo_files": (
            {
                "name": "list_repo_files",
                "description": "List all files and directories in the target GitHub repository.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_repo_files
        ),
        "read_repo_file": (
            {
                "name": "read_repo_file",
                "description": "Read the raw content of a specific file in the repository.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_repo_file
        ),
        "list_documents": (
            {
                "name": "list_documents",
                "description": "List all markdown files available in the Obsidian vault.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_documents
        ),
        "read_document": (
            {
                "name": "read_document",
                "description": "Read the content of a specific markdown file.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The relative path to the markdown file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_document
        ),
        "propose_update": (
            {
                "name": "propose_update",
                "description": "Submit the final updated markdown documentation. You can submit multiple updates at once if multiple files were modified.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "updates": {
                            "type": "array",
                            "description": "List of updates to propose.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "target_file": {
                                        "type": "string",
                                        "description": "The relative path of the file being updated."
                                    },
                                    "proposed_content": {
                                        "type": "string",
                                        "description": "The complete, updated markdown content. Leave empty if deleting."
                                    },
                                    "action": {
                                        "type": "string",
                                        "description": "The action to perform: 'create', 'update', or 'delete'.",
                                        "enum": ["create", "update", "delete"]
                                    }
                                },
                                "required": ["target_file", "proposed_content", "action"]
                            }
                        }
                    },
                    "required": ["updates"]
                }
            },
            None
        )
    }

    try:
        await report_status("Agent drafting documentation...")
        final_args = await agent.run_agent_loop(system_prompt, user_prompt, tools_funcs)
        updates = final_args.get("updates", [])
        
        # Fallback for single update
        if not updates and "proposed_content" in final_args:
            updates = [{"target_file": final_args.get("target_file", req.page_title or "New Document.md"), "proposed_content": final_args.get("proposed_content", "")}]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    pending_ids = []
    for update in updates:
        target_page = update.get("target_file", req.page_title or "New Document.md")
        updated_content = update.get("proposed_content", "")
        action = update.get("action", "update")
        
        page_data = ob_service.get_page_content_by_title(target_page)
        current_content = page_data["content"] if page_data else ""
        page_id = target_page
        version = 1

        pending_id = pending_manager.create_pending_update(
            title=target_page,
            original_content=current_content,
            proposed_content=updated_content,
            page_id=page_id,
            version=version,
            confluence_url=clean_obsidian_path,
            space_key="",
            target_type="obsidian",
            action=action
        )
        pending_ids.append(pending_id)
        
    return {"status": "success", "pending_ids": pending_ids}

class LinearReconcileRequest(BaseModel):
    voice_text: str
    commits: list[str]
    linear_api_token: str
    linear_workspace_id: str = ""
    git_provider: str = "github"
    github_token: str = None
    github_repo: str = None
    gitlab_host: str = "https://gitlab.com"
    gitlab_token: str = None
    gitlab_repo: str = None
    prs: list[int] = None
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "openai/gpt-4o-mini"
    llm_api_key: str = ""
    search_all: bool = False

@app.post("/reconcile/linear")
async def reconcile_linear(req: LinearReconcileRequest):
    await report_status("Fetching remote codebase...")
    print("LINEAR RECONCILE REQ LLM PROVIDER:", req.llm_provider)
    print("LINEAR RECONCILE REQ LLM BASE URL:", req.llm_base_url)
    print("LINEAR RECONCILE REQ LLM MODEL:", req.llm_model)
    print("LINEAR RECONCILE REQ LLM API KEY:", req.llm_api_key)
    
    if req.git_provider.lower() == "gitlab":
        from gitlab_service import GitLabService
        dynamic_git = GitLabService(host=req.gitlab_host, token=req.gitlab_token, repo=req.gitlab_repo)
    else:
        dynamic_git = GitHubService(token=req.github_token, repo=req.github_repo)
        
    commits_info = await dynamic_git.get_commit_info(req.commits) if req.commits else []

    git_formatted = ""
    for c in commits_info:
        if "error" in c: continue
        git_formatted += f"Commit: {c['hexsha']}\\nAuthor: {c['author']}\\nMessage: {c['message']}\\n"
        for diff in c.get("diffs", []):
            diff_text = diff['diff']
            if len(diff_text) > 10000:
                diff_text = diff_text[:10000] + "\n...[DIFF TRUNCATED DUE TO LENGTH]..."
            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\\nDiff:\\n{diff_text}\\n"

    github_formatted = ""
    if req.prs:
        for pr_num in req.prs:
            pr_data = await dynamic_git.get_pr_details(pr_num)
            if "error" not in pr_data:
                github_formatted += f"PR/MR #{pr_data['number']}: {pr_data['title']}\\nDescription: {pr_data['description']}\\n"

    from linear_service import LinearService
    lin_service = LinearService(req.linear_api_token)
    
    from prompts import get_linear_agent_system_prompt, get_linear_agent_user_prompt
    system_prompt = get_linear_agent_system_prompt()
    user_prompt = get_linear_agent_user_prompt(
        voice_text=req.voice_text,
        git_formatted=git_formatted,
        github_formatted=github_formatted
    )
        
    agent = AgentService(req.llm_provider, req.llm_base_url, req.llm_model, req.llm_api_key)
    
    def tool_list_documents():
        docs = lin_service.list_documents(req.linear_workspace_id, req.search_all)
        return "\n".join([f"ID: {d['id']}, Title: {d['title']}" for d in docs])
        
    def tool_read_document(doc_id: str):
        doc = lin_service.get_document(doc_id)
        if doc:
            return doc.get("content", "No content found.")
        return "Document not found."
        
    async def tool_list_repo_files():
        return await dynamic_git.get_repo_tree()
        
    async def tool_read_repo_file(file_path: str):
        return await dynamic_git.get_file_content(file_path)
        
    tools_funcs = {
        "list_repo_files": (
            {
                "name": "list_repo_files",
                "description": "List all files and directories in the target GitHub repository.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_repo_files
        ),
        "read_repo_file": (
            {
                "name": "read_repo_file",
                "description": "Read the raw content of a specific file in the repository.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_repo_file
        ),
        "list_documents": (
            {
                "name": "list_documents",
                "description": "List all available Linear Docs in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_documents
        ),
        "read_document": (
            {
                "name": "read_document",
                "description": "Read the markdown content of a specific Linear Document.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "doc_id": {
                            "type": "string",
                            "description": "The exact ID of the Linear Document (obtained from list_documents)."
                        }
                    },
                    "required": ["doc_id"]
                }
            },
            tool_read_document
        ),
        "propose_update": (
            {
                "name": "propose_update",
                "description": "Submit the final updated or new markdown document. If updating, provide the existing doc_id. If creating a new document, leave doc_id empty and provide a clear title.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "updates": {
                            "type": "array",
                            "description": "List of updates to propose.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "doc_id": {
                                        "type": "string",
                                        "description": "The ID of the document if updating an existing one. Leave blank if creating a new document."
                                    },
                                    "title": {
                                        "type": "string",
                                        "description": "The title of the document."
                                    },
                                    "proposed_content": {
                                        "type": "string",
                                        "description": "The complete, updated or new markdown content."
                                    }
                                },
                                "required": ["title", "proposed_content"]
                            }
                        }
                    },
                    "required": ["updates"]
                }
            },
            None
        )
    }

    try:
        await report_status("Agent drafting documentation...")
        final_args = await agent.run_agent_loop(system_prompt, user_prompt, tools_funcs)
        updates = final_args.get("updates", [])
        
        if not updates and "proposed_content" in final_args:
            updates = [{
                "doc_id": final_args.get("doc_id", ""),
                "title": final_args.get("title", "New Document"),
                "proposed_content": final_args.get("proposed_content", "")
            }]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    pending_ids = []
    for update in updates:
        doc_id = update.get("doc_id", "")
        title = update.get("title", "New Document")
        updated_content = update.get("proposed_content", "")
        
        current_content = ""
        if doc_id:
            doc = lin_service.get_document(doc_id)
            if doc:
                current_content = doc.get("content", "")
                title = doc.get("title", title)
                
        pending_id = pending_manager.create_pending_update(
            title=title,
            original_content=current_content,
            proposed_content=updated_content,
            page_id=doc_id,
            version=1,
            confluence_url=req.linear_workspace_id,
            space_key="",
            target_type="linear"
        )
        pending_ids.append(pending_id)
        
    return {"status": "success", "pending_ids": pending_ids}

class NotionReconcileRequest(BaseModel):
    voice_text: str
    commits: list[str]
    notion_api_key: str
    notion_page_id: str
    page_title: str = "Architecture Overview"
    git_provider: str = "github"
    github_token: str = None
    github_repo: str = None
    gitlab_host: str = "https://gitlab.com"
    gitlab_token: str = None
    gitlab_repo: str = None
    bitbucket_token: str = None
    bitbucket_repo: str = None
    prs: list[int] = None
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "qwen/qwen3.7-plus"
    llm_api_key: str = None

@app.post("/reconcile/notion")
async def reconcile_notion_docs(req: NotionReconcileRequest):
    if req.git_provider == "gitlab":
        from gitlab_service import GitLabService
        dynamic_git = GitLabService(host=req.gitlab_host, token=req.gitlab_token, repo=req.gitlab_repo)
    elif req.git_provider == "bitbucket":
        from bitbucket_service import BitbucketService
        dynamic_git = BitbucketService(token=req.bitbucket_token, repo=req.bitbucket_repo)
    else:
        dynamic_git = GitHubService(token=req.github_token, repo=req.github_repo)

    commits_info = []
    if req.commits:
        for sha in req.commits:
            c_info = await dynamic_git.get_commit_details(sha)
            commits_info.append(c_info)

    git_formatted = ""
    for c in commits_info:
        if "error" in c: continue
        git_formatted += f"Commit: {c['hexsha']}\nAuthor: {c['author']}\nMessage: {c['message']}\n"
        for diff in c.get("diffs", []):
            diff_text = diff['diff']
            if len(diff_text) > 10000:
                diff_text = diff_text[:10000] + "\n...[DIFF TRUNCATED DUE TO LENGTH]..."
            git_formatted += f"File: {diff['a_path']} -> {diff['b_path']}\nDiff:\n{diff_text}\n"

    github_formatted = ""
    if req.prs:
        for pr_num in req.prs:
            pr_data = await dynamic_git.get_pr_details(pr_num)
            if "error" not in pr_data:
                github_formatted += f"PR/MR #{pr_data['number']}: {pr_data['title']}\nDescription: {pr_data['description']}\n"

    from prompts import get_confluence_agent_system_prompt, get_confluence_agent_user_prompt
    
    system_prompt = get_confluence_agent_system_prompt()
    user_prompt = get_confluence_agent_user_prompt(
        voice_text=req.voice_text,
        git_formatted=git_formatted,
        github_formatted=github_formatted,
        page_title=req.page_title or "Architecture Overview"
    )
    
    agent = AgentService(req.llm_provider, req.llm_base_url, req.llm_model, req.llm_api_key)
    
    async def tool_list_repo_files():
        return await dynamic_git.get_repo_tree()
        
    async def tool_read_repo_file(file_path: str):
        return await dynamic_git.get_file_content(file_path)
        
    tools_funcs = {
        "list_repo_files": (
            {
                "name": "list_repo_files",
                "description": "List all files and directories in the target GitHub repository.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_repo_files
        ),
        "read_repo_file": (
            {
                "name": "read_repo_file",
                "description": "Read the raw content of a specific file in the repository.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_repo_file
        ),
        "propose_update": (
            {
                "name": "propose_update",
                "description": "Submit the final updated or new markdown document for Notion.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "updates": {
                            "type": "array",
                            "description": "List of updates to propose.",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "target_file": {
                                        "type": "string",
                                        "description": "The title of the page in Notion."
                                    },
                                    "proposed_content": {
                                        "type": "string",
                                        "description": "The complete, updated or new markdown content."
                                    }
                                },
                                "required": ["target_file", "proposed_content"]
                            }
                        }
                    },
                    "required": ["updates"]
                }
            },
            None
        )
    }

    try:
        await report_status("Agent drafting documentation...")
        final_args = await agent.run_agent_loop(system_prompt, user_prompt, tools_funcs)
        updates = final_args.get("updates", [])
        
        if not updates and "proposed_content" in final_args:
            updates = [{"target_file": req.page_title, "proposed_content": final_args["proposed_content"]}]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    pending_ids = []
    for update in updates:
        target_page = update.get("target_file", req.page_title)
        updated_content = update.get("proposed_content", "")
        
        pending_id = pending_manager.create_pending_update(
            title=target_page,
            original_content="",
            proposed_content=updated_content,
            page_id="",
            version=1,
            confluence_url=req.notion_page_id,
            space_key="",
            target_type="notion"
        )
        pending_ids.append(pending_id)
        
    return {"status": "success", "pending_ids": pending_ids}

@app.get("/pending_updates")
def get_pending_updates():
    return {"status": "success", "updates": pending_manager.get_all()}

@app.get("/updates/history")
def get_updates_history():
    return {"status": "success", "updates": pending_manager.get_history()}

@app.post("/pending_updates/{pending_id}/approve")
async def approve_pending_update(pending_id: str, req: dict):
    item = pending_manager.get_by_id(pending_id)
    if not item:
        raise HTTPException(status_code=404, detail="Pending update not found")
    if item.get("target_type") == "obsidian":
        ob_service = ObsidianService(item["confluence_url"])
        if item.get("action") == "delete":
            ob_service.delete_page(item["title"])
        else:
            ob_service.update_page(item["page_id"], item["title"], item["proposed_content"])
    elif item.get("target_type") == "local":
        file_path = os.path.join(os.getcwd(), item["title"])
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(item["proposed_content"])
    elif item.get("target_type") == "linear":
        from linear_service import LinearService
        lin_api_token = req.get("linear_api_token")
        if not lin_api_token:
            raise HTTPException(status_code=400, detail="Linear API token is required for approval.")
        lin_service = LinearService(lin_api_token)
        if item["page_id"]:
            lin_service.update_document(item["page_id"], item["proposed_content"])
        else:
            workspace_id = item.get("confluence_url", "")
            team_id = workspace_id.replace("team:", "") if workspace_id.startswith("team:") else None
            project_id = workspace_id.replace("project:", "") if workspace_id.startswith("project:") else None
            lin_service.create_document(item["title"], item["proposed_content"], project_id=project_id, team_id=team_id)
    elif item.get("target_type") == "notion":
        from notion_service import NotionService
        notion_api_key = req.get("notion_api_key") or os.getenv("NOTION_API_KEY", "")
        parent_page_id = item.get("confluence_url") or req.get("notion_page_id") or os.getenv("NOTION_PAGE_ID", "")
        notion_service = NotionService(api_key=notion_api_key, parent_page_id=parent_page_id)
        res = await notion_service.upsert_page(item["title"], item["proposed_content"], page_id=item.get("page_id"))
        if res.get("status") == "failed":
            raise HTTPException(status_code=400, detail=res.get("error", "Failed to upload to Notion"))
    else:
        conf_service = ConfluenceService(
            item["confluence_url"], 
            item["space_key"], 
            req.get("username"), 
            req.get("api_token")
        )
        if item["page_id"]:
            await conf_service.update_page(item["page_id"], item["title"], item["proposed_content"], item["version"])
        else:
            await conf_service.create_page(item["title"], item["proposed_content"])
        
    pending_manager.move_to_history(pending_id, "approved")
    return {"status": "success"}

@app.post("/pending_updates/{pending_id}/reject")
def reject_pending_update(pending_id: str):
    pending_manager.move_to_history(pending_id, "rejected")
    return {"status": "success"}

@app.post("/updates/history/{history_id}/reupload")
async def reupload_history_update(history_id: str, req: dict):
    item = pending_manager.get_history_by_id(history_id)
    if not item:
        raise HTTPException(status_code=404, detail="History update not found")
    target_type = item.get("target_type")
    content = item.get("proposed_content", "")
    title = item.get("title", "ARCHITECTURE.md")
    
    if target_type == "obsidian":
        ob_service = ObsidianService(item.get("confluence_url", ""))
        ob_service.update_page(item.get("page_id", ""), title, content)
    elif target_type == "local":
        file_path = os.path.join(os.getcwd(), title)
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(content)
    elif target_type == "linear":
        from linear_service import LinearService
        lin_api_token = req.get("linear_api_token") or os.getenv("LINEAR_API_KEY", "")
        if not lin_api_token:
            raise HTTPException(status_code=400, detail="Linear API token is required for re-upload.")
        lin_service = LinearService(lin_api_token)
        if item.get("page_id"):
            lin_service.update_document(item["page_id"], content)
        else:
            workspace_id = item.get("confluence_url", "")
            team_id = workspace_id.replace("team:", "") if workspace_id.startswith("team:") else None
            project_id = workspace_id.replace("project:", "") if workspace_id.startswith("project:") else None
            lin_service.create_document(title, content, project_id=project_id, team_id=team_id)
    elif target_type == "notion":
        from notion_service import NotionService
        notion_api_key = req.get("notion_api_key") or os.getenv("NOTION_API_KEY", "")
        parent_page_id = item.get("confluence_url") or req.get("notion_page_id") or os.getenv("NOTION_PAGE_ID", "")
        notion_service = NotionService(api_key=notion_api_key, parent_page_id=parent_page_id)
        res = await notion_service.upsert_page(title, content, page_id=item.get("page_id"))
        if res.get("status") == "failed":
            raise HTTPException(status_code=400, detail=res.get("error", "Failed to upload to Notion"))
    else:
        conf_service = ConfluenceService(
            item.get("confluence_url", ""), 
            item.get("space_key", ""), 
            req.get("username"), 
            req.get("api_token")
        )
        if item.get("page_id"):
            await conf_service.update_page(item["page_id"], title, content, item.get("version", 1))
        else:
            await conf_service.create_page(title, content)
            
    return {"status": "success", "message": f"Successfully re-uploaded '{title}' to {target_type}!"}

class NotionTestRequest(BaseModel):
    api_key: str
    parent_page_id: str

@app.post("/notion/test_connection")
async def test_notion_connection(req: NotionTestRequest):
    from notion_service import NotionService
    service = NotionService(api_key=req.api_key, parent_page_id=req.parent_page_id)
    return await service.test_connection()

class ArchitectureReconcileRequest(BaseModel):
    github_token: str
    github_repo: str = ""
    github_branch: str = ""
    git_provider: str = "github"
    gitlab_host: str = "https://gitlab.com"
    gitlab_repo: str = ""
    gitlab_branch: str = ""
    bitbucket_repo: str = ""
    bitbucket_branch: str = ""
    target_type: str = "local"
    target_file: str = "ARCHITECTURE.md"
    confluence_url: str = ""
    linear_api_token: str = ""
    linear_workspace_id: str = ""
    notion_api_key: str = ""
    notion_page_id: str = ""
    voice_text: str = ""
    llm_provider: str = "openrouter"
    llm_base_url: str = "http://localhost:1234/v1"
    llm_model: str = "openai/gpt-4o-mini"
    llm_api_key: str = ""

@app.post("/reconcile/architecture")
async def reconcile_architecture(req: ArchitectureReconcileRequest):
    await report_status("Fetching remote codebase...")
    
    if req.git_provider == "gitlab":
        if not req.gitlab_repo:
            raise HTTPException(status_code=400, detail="GitLab repository is required.")
        repo_name = req.gitlab_repo
    elif req.git_provider == "bitbucket":
        if not req.bitbucket_repo:
            raise HTTPException(status_code=400, detail="Bitbucket repository is required.")
        repo_name = req.bitbucket_repo
    else:
        if not req.github_repo:
            raise HTTPException(status_code=400, detail="GitHub repository is required.")
        repo_name = req.github_repo

    doc_title = req.target_file or "ARCHITECTURE.md"
    if not doc_title.endswith(".md"):
        doc_title += ".md"

    existing_content = ""
    existing_page_id = ""
    
    if req.target_type == "linear" and req.linear_api_token:
        try:
            from linear_service import LinearService
            lin_service = LinearService(req.linear_api_token)
            docs = lin_service.list_documents()
            search_key = doc_title.replace(".md", "").lower()
            arch_doc = next((d for d in docs if search_key in d["title"].lower() or "architecture" in d["title"].lower()), None)
            if arch_doc:
                doc_data = lin_service.get_document(arch_doc["id"])
                if doc_data:
                    existing_content = doc_data.get("content", "")
                    existing_page_id = arch_doc["id"]
        except Exception as e:
            print(f"Error fetching Linear architecture doc: {e}")
            
    elif req.target_type in ["obsidian", "local"] and req.confluence_url:
        try:
            from obsidian_service import ObsidianService
            ob_service = ObsidianService(req.confluence_url)
            page_data = ob_service.get_page_content_by_title(doc_title)
            if page_data:
                existing_content = page_data["content"]
                existing_page_id = doc_title
        except Exception as e:
            print(f"Error fetching Obsidian architecture doc: {e}")

    elif req.target_type == "notion":
        try:
            from notion_service import NotionService
            notion_api_key = req.notion_api_key or os.getenv("NOTION_API_KEY", "")
            parent_page_id = req.notion_page_id or os.getenv("NOTION_PAGE_ID", "")
            notion_svc = NotionService(api_key=notion_api_key, parent_page_id=parent_page_id)
            existing_page_id = await notion_svc.find_child_page_by_title(doc_title) or await notion_svc.find_child_page_by_title("ARCHITECTURE.md") or ""
            if existing_page_id:
                existing_content = await notion_svc.get_page_markdown(existing_page_id)
        except Exception as e:
            print(f"Error fetching Notion architecture doc: {e}")

    if req.git_provider == "gitlab":
        from gitlab_service import GitLabService
        git_service = GitLabService(host=req.gitlab_host, token=req.github_token, repo=req.gitlab_repo)
        if req.gitlab_branch:
            git_service.branch = req.gitlab_branch
    elif req.git_provider == "bitbucket":
        from bitbucket_service import BitbucketService
        git_service = BitbucketService(token=req.github_token, repo=req.bitbucket_repo)
        if req.bitbucket_branch:
            git_service.branch = req.bitbucket_branch
    else:
        git_service = GitHubService(token=req.github_token, repo=req.github_repo)
        if req.github_branch:
            git_service.branch = req.github_branch
    
    repo_tree = await git_service.get_repo_tree()
    if not repo_tree or repo_tree.startswith("Error:") or repo_tree.startswith("Failed") or len(repo_tree.strip()) < 5:
        raise HTTPException(
            status_code=502,
            detail=f"Network/Repository Error: Could not connect to {req.git_provider.capitalize()} or retrieve the repository tree for '{repo_name}'. Please verify your internet connection and repository access permissions."
        )
    
    from prompts import get_architecture_system_prompt, get_architecture_user_prompt
    
    system_prompt = get_architecture_system_prompt()
    user_prompt = get_architecture_user_prompt(github_repo=repo_name, voice_text=req.voice_text, existing_content=existing_content, repo_tree=repo_tree)
    
    agent = AgentService(req.llm_provider, req.llm_base_url, req.llm_model, req.llm_api_key)
    
    async def tool_list_repo_files():
        return await git_service.get_repo_tree()
        
    async def tool_read_repo_file(file_path: str):
        content = await git_service.get_file_content(file_path)
        if not content:
            return "File is empty or not found."
        lines = content.splitlines()
        if len(lines) > 100 or len(content) > 3500:
            truncated = "\n".join(lines[:100])[:3500]
            return f"{truncated}\n\n... [Truncated: File contains {len(lines)} lines total. Showing first 100 lines for architectural overview.]"
        return content
        
    tools_funcs = {
        "list_repo_files": (
            {
                "name": "list_repo_files",
                "description": "List all files and directories in the target GitHub repository.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            },
            tool_list_repo_files
        ),
        "read_repo_file": (
            {
                "name": "read_repo_file",
                "description": "Read the raw content of a specific file in the repository.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file."
                        }
                    },
                    "required": ["file_path"]
                }
            },
            tool_read_repo_file
        ),
        "propose_update": (
            {
                "name": "propose_update",
                "description": "Submit the final architecture documentation.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "proposed_content": {
                            "type": "string",
                            "description": "The complete markdown documentation for the architecture."
                        }
                    },
                    "required": ["proposed_content"]
                }
            },
            None
        )
    }

    try:
        await report_status("Agent drafting documentation...")
        final_args = await agent.run_agent_loop(system_prompt, user_prompt, tools_funcs, max_steps=3)
        raw_updated_content = (final_args.get("proposed_content") or final_args.get("content") or final_args.get("markdown") or "").strip()
        updated_content = clean_markdown_documentation(raw_updated_content)
        
        lower_content = updated_content.lower()
        inability_phrases = [
            "unable to retrieve", "name or service not known", "network path can't be resolved",
            "without access to the repository", "cannot access the repository", "could not retrieve repository",
            "network error", "dns error", "error: could not", "i'm unable to", "i am unable to"
        ]
        if any(phrase in lower_content for phrase in inability_phrases) or (not updated_content.startswith("#") and "architecture" not in lower_content and len(updated_content) < 200):
            raise HTTPException(
                status_code=502,
                detail=f"Generation Failed: The AI could not access the codebase due to network/access issues: {updated_content[:250]}"
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    target_destination_url = req.notion_page_id if req.target_type == "notion" else (req.linear_workspace_id if req.target_type == "linear" else req.confluence_url)

    pending_id = pending_manager.create_pending_update(
        title=doc_title,
        original_content=existing_content if existing_content else "New File: This file does not exist yet.",
        proposed_content=updated_content,
        page_id=existing_page_id,
        version=1,
        confluence_url=target_destination_url,
        space_key="",
        target_type=req.target_type
    )
    return {"status": "success", "pending_id": pending_id}
